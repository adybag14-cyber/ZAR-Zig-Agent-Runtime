# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 30,
    [int] $GdbPort = 1238
)

$ErrorActionPreference = "Stop"

$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$releaseDir = Join-Path $repo "release"
$selectiveProbeScript = Join-Path $PSScriptRoot "baremetal-qemu-wake-queue-selective-probe-check.ps1"
$artifact = Join-Path $releaseDir "openclaw-zig-baremetal-pvh-wake-queue-selective-probe.elf"
$gdbScript = Join-Path $releaseDir "qemu-wake-queue-summary-age-probe.gdb"
$gdbStdout = Join-Path $releaseDir "qemu-wake-queue-summary-age-probe.gdb.stdout.log"
$gdbStderr = Join-Path $releaseDir "qemu-wake-queue-summary-age-probe.gdb.stderr.log"
$qemuStdout = Join-Path $releaseDir "qemu-wake-queue-summary-age-probe.qemu.stdout.log"
$qemuStderr = Join-Path $releaseDir "qemu-wake-queue-summary-age-probe.qemu.stderr.log"

$schedulerResetOpcode = 26
$timerResetOpcode = 41
$wakeQueueClearOpcode = 44
$resetInterruptCountersOpcode = 8
$taskCreateOpcode = 27
$schedulerDisableOpcode = 25
$taskWaitForOpcode = 53
$taskWaitInterruptOpcode = 57
$triggerInterruptOpcode = 7
$taskWaitOpcode = 50
$schedulerWakeTaskOpcode = 45
$wakeQueuePopReasonVectorOpcode = 62

$taskBudget = 5
$taskPriority = 0
$timerDelay = 2
$interruptVectorA = 13
$interruptVectorB = 31
$postProbeSlackTicks = 4
$summaryAgeQuantum = 2

$taskIdTimer = 1
$taskIdInterruptA1 = 2
$taskIdInterruptA2 = 3
$taskIdInterruptB = 4
$taskIdManual = 5

$wakeReasonTimer = 1
$wakeReasonInterrupt = 2
$wakeReasonManual = 3

$statusTicksOffset = 8
$statusCommandSeqAckOffset = 28
$statusLastCommandOpcodeOffset = 32
$statusLastCommandResultOffset = 34

$commandOpcodeOffset = 6
$commandSeqOffset = 8
$commandArg0Offset = 16
$commandArg1Offset = 24

$wakeEventStride = 32
$wakeEventTaskIdOffset = 4
$wakeEventReasonOffset = 12
$wakeEventVectorOffset = 13
$wakeEventTickOffset = 16

$summaryLenOffset = 0
$summaryOverflowOffset = 4
$summaryTimerCountOffset = 8
$summaryInterruptCountOffset = 12
$summaryManualCountOffset = 16
$summaryNonzeroVectorCountOffset = 20
$summaryStaleCountOffset = 24
$summaryOldestTickOffset = 32
$summaryNewestTickOffset = 40

$ageCurrentTickOffset = 0
$ageQuantumTicksOffset = 8
$ageStaleCountOffset = 16
$ageStaleOlderThanQuantumCountOffset = 20
$ageFutureCountOffset = 24

function Resolve-QemuExecutable {
    $candidates = @(
        "qemu-system-x86_64",
        "qemu-system-x86_64.exe",
        "C:\Program Files\qemu\qemu-system-x86_64.exe"
    )

    foreach ($name in $candidates) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($null -ne $cmd -and $cmd.Path) {
            return $cmd.Path
        }
        if (Test-Path $name) {
            return (Resolve-Path $name).Path
        }
    }

    return $null
}

function Resolve-GdbExecutable {
    $candidates = @("gdb", "gdb.exe")
    foreach ($name in $candidates) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($null -ne $cmd -and $cmd.Path) {
            return $cmd.Path
        }
    }
    return $null
}

function Resolve-NmExecutable {
    $candidates = @(
        "llvm-nm",
        "llvm-nm.exe",
        "nm",
        "nm.exe",
        "C:\Users\Ady\Documents\starpro\tooling\emsdk\upstream\bin\llvm-nm.exe"
    )

    foreach ($name in $candidates) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($null -ne $cmd -and $cmd.Path) {
            return $cmd.Path
        }
        if (Test-Path $name) {
            return (Resolve-Path $name).Path
        }
    }

    return $null
}

function Resolve-SymbolAddress {
    param(
        [string[]] $SymbolLines,
        [string] $Pattern,
        [string] $SymbolName
    )

    $line = $SymbolLines | Where-Object { $_ -match $Pattern } | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($line)) {
        throw "Failed to resolve symbol address for $SymbolName"
    }

    $parts = ($line.Trim() -split '\s+')
    if ($parts.Count -lt 3) {
        throw "Unexpected symbol line while resolving ${SymbolName}: $line"
    }

    return $parts[0]
}

function Extract-IntValue {
    param(
        [string] $Text,
        [string] $Name
    )

    $pattern = [regex]::Escape($Name) + '=(-?\d+)'
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) {
        throw "Failed to extract $Name from probe output."
    }

    return [long]$match.Groups[1].Value
}

function Invoke-SelectiveArtifactBuildIfNeeded {
    param(
        [switch] $Force
    )

    if ($SkipBuild -and $Force) {
        throw "Selective probe artifact is stale or missing and -SkipBuild was supplied."
    }
    if ($SkipBuild -and -not (Test-Path $artifact)) {
        throw "Selective probe artifact not found at $artifact and -SkipBuild was supplied."
    }

    if ($SkipBuild -and -not $Force) {
        return
    }

    if (-not (Test-Path $selectiveProbeScript)) {
        throw "Prerequisite script not found: $selectiveProbeScript"
    }

    & $selectiveProbeScript
    if ($LASTEXITCODE -ne 0) {
        throw "Selective wake-queue probe prerequisite failed with exit code $LASTEXITCODE"
    }
}

$qemu = Resolve-QemuExecutable
if ($null -eq $qemu) {
    Write-Output "BAREMETAL_QEMU_AVAILABLE=False"
    Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE=skipped"
    exit 0
}

$gdb = Resolve-GdbExecutable
if ($null -eq $gdb) {
    Write-Output "BAREMETAL_GDB_AVAILABLE=False"
    Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE=skipped"
    exit 0
}

$nm = Resolve-NmExecutable
if ($null -eq $nm) {
    Write-Output "BAREMETAL_NM_AVAILABLE=False"
    Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE=skipped"
    exit 0
}

if (-not (Test-Path $artifact)) {
    Invoke-SelectiveArtifactBuildIfNeeded
}

$symbolOutput = & $nm $artifact
if ($LASTEXITCODE -ne 0 -or $null -eq $symbolOutput -or $symbolOutput.Count -eq 0) {
    throw "Failed to resolve symbol table from $artifact using $nm"
}

$hasSummaryPtr = $symbolOutput | Where-Object { $_ -match '\s[Tt]\soc_wake_queue_summary_ptr$' } | Select-Object -First 1
$hasAgePtr = $symbolOutput | Where-Object { $_ -match '\s[Tt]\soc_wake_queue_age_buckets_ptr$' } | Select-Object -First 1
$hasAgePtrQuantum2 = $symbolOutput | Where-Object { $_ -match '\s[Tt]\soc_wake_queue_age_buckets_ptr_quantum_2$' } | Select-Object -First 1
if (($null -eq $hasSummaryPtr -or $null -eq $hasAgePtr -or $null -eq $hasAgePtrQuantum2) -and -not $SkipBuild) {
    Invoke-SelectiveArtifactBuildIfNeeded -Force
    $symbolOutput = & $nm $artifact
    if ($LASTEXITCODE -ne 0 -or $null -eq $symbolOutput -or $symbolOutput.Count -eq 0) {
        throw "Failed to resolve symbol table from $artifact using $nm after rebuild"
    }
}

$startAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[Tt]\s_start$' -SymbolName "_start"
$spinPauseAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[tT]\sbaremetal_main\.spinPause$' -SymbolName "baremetal_main.spinPause"
$statusAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[dDbB]\sbaremetal_main\.status$' -SymbolName "baremetal_main.status"
$commandMailboxAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[dDbB]\sbaremetal_main\.command_mailbox$' -SymbolName "baremetal_main.command_mailbox"
$wakeQueueAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[dDbB]\sbaremetal_main\.wake_queue$' -SymbolName "baremetal_main.wake_queue"
$wakeQueueCountAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[dDbB]\sbaremetal_main\.wake_queue_count$' -SymbolName "baremetal_main.wake_queue_count"
$wakeQueueSummaryPtrAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[Tt]\soc_wake_queue_summary_ptr$' -SymbolName "oc_wake_queue_summary_ptr"
$wakeQueueAgeBucketsPtrAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[Tt]\soc_wake_queue_age_buckets_ptr$' -SymbolName "oc_wake_queue_age_buckets_ptr"
$wakeQueueAgeBucketsPtrQuantum2Address = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[Tt]\soc_wake_queue_age_buckets_ptr_quantum_2$' -SymbolName "oc_wake_queue_age_buckets_ptr_quantum_2"
$artifactForGdb = $artifact.Replace('\', '/')

if (Test-Path $gdbStdout) { Remove-Item -Force $gdbStdout }
if (Test-Path $gdbStderr) { Remove-Item -Force $gdbStderr }
if (Test-Path $qemuStdout) { Remove-Item -Force $qemuStdout }
if (Test-Path $qemuStderr) { Remove-Item -Force $qemuStderr }
@"
set pagination off
set confirm off
set `$stage = 0
set `$final_tick_target = 0
set `$stable_tick = 0
set `$pre_current_tick = 0
set `$pre_len = 0
set `$post_current_tick = 0
set `$post_len = 0
set `$pre_summary_len = 0
set `$pre_summary_overflow = 0
set `$pre_summary_timer_count = 0
set `$pre_summary_interrupt_count = 0
set `$pre_summary_manual_count = 0
set `$pre_summary_nonzero_vector_count = 0
set `$pre_summary_stale_count = 0
set `$pre_summary_oldest_tick = 0
set `$pre_summary_newest_tick = 0
set `$pre_age_current_tick = 0
set `$pre_age_quantum_ticks = 0
set `$pre_age_stale_count = 0
set `$pre_age_stale_older_than_quantum_count = 0
set `$pre_age_future_count = 0
set `$post_summary_len = 0
set `$post_summary_overflow = 0
set `$post_summary_timer_count = 0
set `$post_summary_interrupt_count = 0
set `$post_summary_manual_count = 0
set `$post_summary_nonzero_vector_count = 0
set `$post_summary_stale_count = 0
set `$post_summary_oldest_tick = 0
set `$post_summary_newest_tick = 0
set `$post_age_current_tick = 0
set `$post_age_quantum_ticks = 0
set `$post_age_stale_count = 0
set `$post_age_stale_older_than_quantum_count = 0
set `$post_age_future_count = 0
set `$pre_task0 = 0
set `$pre_task1 = 0
set `$pre_task2 = 0
set `$pre_task3 = 0
set `$pre_task4 = 0
set `$pre_reason0 = 0
set `$pre_reason1 = 0
set `$pre_reason2 = 0
set `$pre_reason3 = 0
set `$pre_reason4 = 0
set `$pre_vector0 = 0
set `$pre_vector1 = 0
set `$pre_vector2 = 0
set `$pre_vector3 = 0
set `$pre_vector4 = 0
set `$pre_tick0 = 0
set `$pre_tick1 = 0
set `$pre_tick2 = 0
set `$pre_tick3 = 0
set `$pre_tick4 = 0
set `$post_task0 = 0
set `$post_task1 = 0
set `$post_task2 = 0
set `$post_task3 = 0
file $artifactForGdb
handle SIGQUIT nostop noprint pass
target remote :$GdbPort
break *0x$startAddress
commands
silent
printf "HIT_START\n"
set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $schedulerResetOpcode
set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = 1
set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = 0
set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = 0
set `$stage = 1
continue
end
break *0x$spinPauseAddress
commands
silent
if `$stage == 1
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == 1
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $timerResetOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = 2
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = 0
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = 0
    set `$stage = 2
  end
  continue
end
if `$stage == 2
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == 2
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $wakeQueueClearOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = 3
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = 0
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = 0
    set `$stage = 3
  end
  continue
end
if `$stage == 3
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == 3
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $resetInterruptCountersOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = 4
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = 0
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = 0
    set `$stage = 4
  end
  continue
end
if `$stage == 4
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == 4
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $schedulerDisableOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = 5
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = 0
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = 0
    set `$stage = 5
  end
  continue
end
if `$stage == 5
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == 5
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $taskCreateOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = 6
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = $taskBudget
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = $taskPriority
    set `$stage = 6
  end
  continue
end
if `$stage == 6
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == 6
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $taskWaitForOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = 7
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = $taskIdTimer
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = $timerDelay
    set `$stage = 7
  end
  continue
end
if `$stage == 7
  if *(unsigned int*)(0x$wakeQueueCountAddress) == 1 && *(unsigned int*)(0x$wakeQueueAddress+$wakeEventTaskIdOffset) == $taskIdTimer
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $taskCreateOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = 8
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = $taskBudget
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = $taskPriority
    set `$stage = 8
  end
  continue
end
if `$stage == 8
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == 8
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $taskWaitInterruptOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = 9
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = $taskIdInterruptA1
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = $interruptVectorA
    set `$stage = 9
  end
  continue
end
if `$stage == 9
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == 9
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $triggerInterruptOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = 10
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = $interruptVectorA
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = 0
    set `$stage = 10
  end
  continue
end
if `$stage == 10
  if *(unsigned int*)(0x$wakeQueueCountAddress) == 2 && *(unsigned int*)(0x$wakeQueueAddress+($wakeEventStride*1)+$wakeEventTaskIdOffset) == $taskIdInterruptA1
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $taskCreateOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = 11
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = $taskBudget
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = $taskPriority
    set `$stage = 11
  end
  continue
end
if `$stage == 11
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == 11
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $taskWaitInterruptOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = 12
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = $taskIdInterruptA2
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = $interruptVectorA
    set `$stage = 12
  end
  continue
end
if `$stage == 12
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == 12
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $triggerInterruptOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = 13
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = $interruptVectorA
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = 0
    set `$stage = 13
  end
  continue
end
if `$stage == 13
  if *(unsigned int*)(0x$wakeQueueCountAddress) == 3 && *(unsigned int*)(0x$wakeQueueAddress+($wakeEventStride*2)+$wakeEventTaskIdOffset) == $taskIdInterruptA2
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $taskCreateOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = 14
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = $taskBudget
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = $taskPriority
    set `$stage = 14
  end
  continue
end
if `$stage == 14
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == 14
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $taskWaitInterruptOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = 15
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = $taskIdInterruptB
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = $interruptVectorB
    set `$stage = 15
  end
  continue
end
if `$stage == 15
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == 15
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $triggerInterruptOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = 16
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = $interruptVectorB
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = 0
    set `$stage = 16
  end
  continue
end
if `$stage == 16
  if *(unsigned int*)(0x$wakeQueueCountAddress) == 4 && *(unsigned int*)(0x$wakeQueueAddress+($wakeEventStride*3)+$wakeEventTaskIdOffset) == $taskIdInterruptB
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $taskCreateOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = 17
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = $taskBudget
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = $taskPriority
    set `$stage = 17
  end
  continue
end
if `$stage == 17
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == 17
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $taskWaitOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = 18
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = $taskIdManual
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = 0
    set `$stage = 18
  end
  continue
end
if `$stage == 18
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == 18
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $schedulerWakeTaskOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = 19
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = $taskIdManual
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = 0
    set `$stage = 19
  end
  continue
end
if `$stage == 19
  if *(unsigned int*)(0x$wakeQueueCountAddress) == 5 && *(unsigned int*)(0x$wakeQueueAddress+$wakeEventTaskIdOffset) == $taskIdTimer && *(unsigned int*)(0x$wakeQueueAddress+($wakeEventStride*1)+$wakeEventTaskIdOffset) == $taskIdInterruptA1 && *(unsigned int*)(0x$wakeQueueAddress+($wakeEventStride*2)+$wakeEventTaskIdOffset) == $taskIdInterruptA2 && *(unsigned int*)(0x$wakeQueueAddress+($wakeEventStride*3)+$wakeEventTaskIdOffset) == $taskIdInterruptB && *(unsigned int*)(0x$wakeQueueAddress+($wakeEventStride*4)+$wakeEventTaskIdOffset) == $taskIdManual
    set `$pre_current_tick = *(unsigned long long*)(0x$statusAddress+$statusTicksOffset)
    set `$pre_len = *(unsigned int*)(0x$wakeQueueCountAddress)
    set `$pre_task0 = *(unsigned int*)(0x$wakeQueueAddress+$wakeEventTaskIdOffset)
    set `$pre_task1 = *(unsigned int*)(0x$wakeQueueAddress+($wakeEventStride*1)+$wakeEventTaskIdOffset)
    set `$pre_task2 = *(unsigned int*)(0x$wakeQueueAddress+($wakeEventStride*2)+$wakeEventTaskIdOffset)
    set `$pre_task3 = *(unsigned int*)(0x$wakeQueueAddress+($wakeEventStride*3)+$wakeEventTaskIdOffset)
    set `$pre_task4 = *(unsigned int*)(0x$wakeQueueAddress+($wakeEventStride*4)+$wakeEventTaskIdOffset)
    set `$pre_reason0 = *(unsigned char*)(0x$wakeQueueAddress+$wakeEventReasonOffset)
    set `$pre_reason1 = *(unsigned char*)(0x$wakeQueueAddress+($wakeEventStride*1)+$wakeEventReasonOffset)
    set `$pre_reason2 = *(unsigned char*)(0x$wakeQueueAddress+($wakeEventStride*2)+$wakeEventReasonOffset)
    set `$pre_reason3 = *(unsigned char*)(0x$wakeQueueAddress+($wakeEventStride*3)+$wakeEventReasonOffset)
    set `$pre_reason4 = *(unsigned char*)(0x$wakeQueueAddress+($wakeEventStride*4)+$wakeEventReasonOffset)
    set `$pre_vector0 = *(unsigned char*)(0x$wakeQueueAddress+$wakeEventVectorOffset)
    set `$pre_vector1 = *(unsigned char*)(0x$wakeQueueAddress+($wakeEventStride*1)+$wakeEventVectorOffset)
    set `$pre_vector2 = *(unsigned char*)(0x$wakeQueueAddress+($wakeEventStride*2)+$wakeEventVectorOffset)
    set `$pre_vector3 = *(unsigned char*)(0x$wakeQueueAddress+($wakeEventStride*3)+$wakeEventVectorOffset)
    set `$pre_vector4 = *(unsigned char*)(0x$wakeQueueAddress+($wakeEventStride*4)+$wakeEventVectorOffset)
    set `$pre_tick0 = *(unsigned long long*)(0x$wakeQueueAddress+$wakeEventTickOffset)
    set `$pre_tick1 = *(unsigned long long*)(0x$wakeQueueAddress+($wakeEventStride*1)+$wakeEventTickOffset)
    set `$pre_tick2 = *(unsigned long long*)(0x$wakeQueueAddress+($wakeEventStride*2)+$wakeEventTickOffset)
    set `$pre_tick3 = *(unsigned long long*)(0x$wakeQueueAddress+($wakeEventStride*3)+$wakeEventTickOffset)
    set `$pre_tick4 = *(unsigned long long*)(0x$wakeQueueAddress+($wakeEventStride*4)+$wakeEventTickOffset)
    set `$pre_summary_ptr = ((unsigned long long (*)())0x$wakeQueueSummaryPtrAddress)()
    set `$pre_age_ptr = ((unsigned long long (*)())0x$wakeQueueAgeBucketsPtrQuantum2Address)()
    set `$pre_summary_len = *(unsigned int*)(`$pre_summary_ptr+$summaryLenOffset)
    set `$pre_summary_overflow = *(unsigned int*)(`$pre_summary_ptr+$summaryOverflowOffset)
    set `$pre_summary_timer_count = *(unsigned int*)(`$pre_summary_ptr+$summaryTimerCountOffset)
    set `$pre_summary_interrupt_count = *(unsigned int*)(`$pre_summary_ptr+$summaryInterruptCountOffset)
    set `$pre_summary_manual_count = *(unsigned int*)(`$pre_summary_ptr+$summaryManualCountOffset)
    set `$pre_summary_nonzero_vector_count = *(unsigned int*)(`$pre_summary_ptr+$summaryNonzeroVectorCountOffset)
    set `$pre_summary_stale_count = *(unsigned int*)(`$pre_summary_ptr+$summaryStaleCountOffset)
    set `$pre_summary_oldest_tick = *(unsigned long long*)(`$pre_summary_ptr+$summaryOldestTickOffset)
    set `$pre_summary_newest_tick = *(unsigned long long*)(`$pre_summary_ptr+$summaryNewestTickOffset)
    set `$pre_age_current_tick = *(unsigned long long*)(`$pre_age_ptr+$ageCurrentTickOffset)
    set `$pre_age_quantum_ticks = *(unsigned long long*)(`$pre_age_ptr+$ageQuantumTicksOffset)
    set `$pre_age_stale_count = *(unsigned int*)(`$pre_age_ptr+$ageStaleCountOffset)
    set `$pre_age_stale_older_than_quantum_count = *(unsigned int*)(`$pre_age_ptr+$ageStaleOlderThanQuantumCountOffset)
    set `$pre_age_future_count = *(unsigned int*)(`$pre_age_ptr+$ageFutureCountOffset)
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $wakeQueuePopReasonVectorOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = 20
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = $wakeReasonInterrupt | ($interruptVectorA << 8)
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = 1
    set `$stage = 20
  end
  continue
end
if `$stage == 20
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == 20 && *(unsigned int*)(0x$wakeQueueCountAddress) == 4 && *(unsigned int*)(0x$wakeQueueAddress+$wakeEventTaskIdOffset) == $taskIdTimer && *(unsigned int*)(0x$wakeQueueAddress+($wakeEventStride*1)+$wakeEventTaskIdOffset) == $taskIdInterruptA2 && *(unsigned int*)(0x$wakeQueueAddress+($wakeEventStride*2)+$wakeEventTaskIdOffset) == $taskIdInterruptB && *(unsigned int*)(0x$wakeQueueAddress+($wakeEventStride*3)+$wakeEventTaskIdOffset) == $taskIdManual
    set `$post_current_tick = *(unsigned long long*)(0x$statusAddress+$statusTicksOffset)
    set `$post_len = *(unsigned int*)(0x$wakeQueueCountAddress)
    set `$post_task0 = *(unsigned int*)(0x$wakeQueueAddress+$wakeEventTaskIdOffset)
    set `$post_task1 = *(unsigned int*)(0x$wakeQueueAddress+($wakeEventStride*1)+$wakeEventTaskIdOffset)
    set `$post_task2 = *(unsigned int*)(0x$wakeQueueAddress+($wakeEventStride*2)+$wakeEventTaskIdOffset)
    set `$post_task3 = *(unsigned int*)(0x$wakeQueueAddress+($wakeEventStride*3)+$wakeEventTaskIdOffset)
    set `$post_summary_ptr = ((unsigned long long (*)())0x$wakeQueueSummaryPtrAddress)()
    set `$post_age_ptr = ((unsigned long long (*)())0x$wakeQueueAgeBucketsPtrQuantum2Address)()
    set `$post_summary_len = *(unsigned int*)(`$post_summary_ptr+$summaryLenOffset)
    set `$post_summary_overflow = *(unsigned int*)(`$post_summary_ptr+$summaryOverflowOffset)
    set `$post_summary_timer_count = *(unsigned int*)(`$post_summary_ptr+$summaryTimerCountOffset)
    set `$post_summary_interrupt_count = *(unsigned int*)(`$post_summary_ptr+$summaryInterruptCountOffset)
    set `$post_summary_manual_count = *(unsigned int*)(`$post_summary_ptr+$summaryManualCountOffset)
    set `$post_summary_nonzero_vector_count = *(unsigned int*)(`$post_summary_ptr+$summaryNonzeroVectorCountOffset)
    set `$post_summary_stale_count = *(unsigned int*)(`$post_summary_ptr+$summaryStaleCountOffset)
    set `$post_summary_oldest_tick = *(unsigned long long*)(`$post_summary_ptr+$summaryOldestTickOffset)
    set `$post_summary_newest_tick = *(unsigned long long*)(`$post_summary_ptr+$summaryNewestTickOffset)
    set `$post_age_current_tick = *(unsigned long long*)(`$post_age_ptr+$ageCurrentTickOffset)
    set `$post_age_quantum_ticks = *(unsigned long long*)(`$post_age_ptr+$ageQuantumTicksOffset)
    set `$post_age_stale_count = *(unsigned int*)(`$post_age_ptr+$ageStaleCountOffset)
    set `$post_age_stale_older_than_quantum_count = *(unsigned int*)(`$post_age_ptr+$ageStaleOlderThanQuantumCountOffset)
    set `$post_age_future_count = *(unsigned int*)(`$post_age_ptr+$ageFutureCountOffset)
    set `$final_tick_target = `$post_current_tick + $postProbeSlackTicks
    set `$stage = 21
  end
  continue
end
if `$stage == 21
  if *(unsigned long long*)(0x$statusAddress+$statusTicksOffset) >= `$final_tick_target && *(unsigned int*)(0x$wakeQueueCountAddress) == 4
    set `$stable_tick = *(unsigned long long*)(0x$statusAddress+$statusTicksOffset)
    set `$stage = 22
  end
  continue
end
printf "AFTER_WAKE_QUEUE_SUMMARY_AGE\n"
printf "ACK=%u\n", *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset)
printf "LAST_OPCODE=%u\n", *(unsigned short*)(0x$statusAddress+$statusLastCommandOpcodeOffset)
printf "LAST_RESULT=%d\n", *(short*)(0x$statusAddress+$statusLastCommandResultOffset)
printf "TICKS=%llu\n", *(unsigned long long*)(0x$statusAddress+$statusTicksOffset)
printf "MAILBOX_OPCODE=%u\n", *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset)
printf "MAILBOX_SEQ=%u\n", *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset)
printf "PRE_CURRENT_TICK=%llu\n", `$pre_current_tick
printf "PRE_LEN=%u\n", `$pre_len
printf "PRE_TASK0=%u\n", `$pre_task0
printf "PRE_TASK1=%u\n", `$pre_task1
printf "PRE_TASK2=%u\n", `$pre_task2
printf "PRE_TASK3=%u\n", `$pre_task3
printf "PRE_TASK4=%u\n", `$pre_task4
printf "PRE_REASON0=%u\n", `$pre_reason0
printf "PRE_REASON1=%u\n", `$pre_reason1
printf "PRE_REASON2=%u\n", `$pre_reason2
printf "PRE_REASON3=%u\n", `$pre_reason3
printf "PRE_REASON4=%u\n", `$pre_reason4
printf "PRE_VECTOR0=%u\n", `$pre_vector0
printf "PRE_VECTOR1=%u\n", `$pre_vector1
printf "PRE_VECTOR2=%u\n", `$pre_vector2
printf "PRE_VECTOR3=%u\n", `$pre_vector3
printf "PRE_VECTOR4=%u\n", `$pre_vector4
printf "PRE_TICK0=%llu\n", `$pre_tick0
printf "PRE_TICK1=%llu\n", `$pre_tick1
printf "PRE_TICK2=%llu\n", `$pre_tick2
printf "PRE_TICK3=%llu\n", `$pre_tick3
printf "PRE_TICK4=%llu\n", `$pre_tick4
printf "PRE_SUMMARY_LEN=%u\n", `$pre_summary_len
printf "PRE_SUMMARY_OVERFLOW=%u\n", `$pre_summary_overflow
printf "PRE_SUMMARY_TIMER_COUNT=%u\n", `$pre_summary_timer_count
printf "PRE_SUMMARY_INTERRUPT_COUNT=%u\n", `$pre_summary_interrupt_count
printf "PRE_SUMMARY_MANUAL_COUNT=%u\n", `$pre_summary_manual_count
printf "PRE_SUMMARY_NONZERO_VECTOR_COUNT=%u\n", `$pre_summary_nonzero_vector_count
printf "PRE_SUMMARY_STALE_COUNT=%u\n", `$pre_summary_stale_count
printf "PRE_SUMMARY_OLDEST_TICK=%llu\n", `$pre_summary_oldest_tick
printf "PRE_SUMMARY_NEWEST_TICK=%llu\n", `$pre_summary_newest_tick
printf "PRE_AGE_CURRENT_TICK=%llu\n", `$pre_age_current_tick
printf "PRE_AGE_QUANTUM_TICKS=%llu\n", `$pre_age_quantum_ticks
printf "PRE_AGE_STALE_COUNT=%u\n", `$pre_age_stale_count
printf "PRE_AGE_STALE_OLDER_THAN_QUANTUM_COUNT=%u\n", `$pre_age_stale_older_than_quantum_count
printf "PRE_AGE_FUTURE_COUNT=%u\n", `$pre_age_future_count
printf "POST_CURRENT_TICK=%llu\n", `$post_current_tick
printf "POST_LEN=%u\n", `$post_len
printf "POST_TASK0=%u\n", `$post_task0
printf "POST_TASK1=%u\n", `$post_task1
printf "POST_TASK2=%u\n", `$post_task2
printf "POST_TASK3=%u\n", `$post_task3
printf "POST_SUMMARY_LEN=%u\n", `$post_summary_len
printf "POST_SUMMARY_OVERFLOW=%u\n", `$post_summary_overflow
printf "POST_SUMMARY_TIMER_COUNT=%u\n", `$post_summary_timer_count
printf "POST_SUMMARY_INTERRUPT_COUNT=%u\n", `$post_summary_interrupt_count
printf "POST_SUMMARY_MANUAL_COUNT=%u\n", `$post_summary_manual_count
printf "POST_SUMMARY_NONZERO_VECTOR_COUNT=%u\n", `$post_summary_nonzero_vector_count
printf "POST_SUMMARY_STALE_COUNT=%u\n", `$post_summary_stale_count
printf "POST_SUMMARY_OLDEST_TICK=%llu\n", `$post_summary_oldest_tick
printf "POST_SUMMARY_NEWEST_TICK=%llu\n", `$post_summary_newest_tick
printf "POST_AGE_CURRENT_TICK=%llu\n", `$post_age_current_tick
printf "POST_AGE_QUANTUM_TICKS=%llu\n", `$post_age_quantum_ticks
printf "POST_AGE_STALE_COUNT=%u\n", `$post_age_stale_count
printf "POST_AGE_STALE_OLDER_THAN_QUANTUM_COUNT=%u\n", `$post_age_stale_older_than_quantum_count
printf "POST_AGE_FUTURE_COUNT=%u\n", `$post_age_future_count
printf "FINAL_QUEUE_COUNT=%u\n", *(unsigned int*)(0x$wakeQueueCountAddress)
printf "FINAL_STABLE_TICK=%llu\n", `$stable_tick
quit
end
continue
"@ | Set-Content -Path $gdbScript -Encoding Ascii

$qemuArgs = @(
    "-kernel", $artifact,
    "-nographic",
    "-no-reboot",
    "-no-shutdown",
    "-serial", "none",
    "-monitor", "none",
    "-S",
    "-gdb", "tcp::$GdbPort"
)

$qemuProc = Start-Process -FilePath $qemu -ArgumentList $qemuArgs -PassThru -NoNewWindow -RedirectStandardOutput $qemuStdout -RedirectStandardError $qemuStderr
Start-Sleep -Milliseconds 700

$gdbArgs = @("-q", "-batch", "-x", $gdbScript)
$gdbProc = Start-Process -FilePath $gdb -ArgumentList $gdbArgs -PassThru -NoNewWindow -RedirectStandardOutput $gdbStdout -RedirectStandardError $gdbStderr

$timedOut = $false
try {
    $null = Wait-Process -Id $gdbProc.Id -Timeout $TimeoutSeconds -ErrorAction Stop
}
catch {
    $timedOut = $true
    try { Stop-Process -Id $gdbProc.Id -Force -ErrorAction SilentlyContinue } catch {}
}
finally {
    try { Stop-Process -Id $qemuProc.Id -Force -ErrorAction SilentlyContinue } catch {}
}
$hitStart = $false
$hitAfterWakeQueueSummaryAge = $false
$ack = $null
$lastOpcode = $null
$lastResult = $null
$ticks = $null
$mailboxOpcode = $null
$mailboxSeq = $null
$preCurrentTick = $null
$preLen = $null
$preTasks = @()
$preReasons = @()
$preVectors = @()
$preTicks = @()
$preSummaryLen = $null
$preSummaryOverflow = $null
$preSummaryTimerCount = $null
$preSummaryInterruptCount = $null
$preSummaryManualCount = $null
$preSummaryNonzeroVectorCount = $null
$preSummaryStaleCount = $null
$preSummaryOldestTick = $null
$preSummaryNewestTick = $null
$preAgeCurrentTick = $null
$preAgeQuantumTicks = $null
$preAgeStaleCount = $null
$preAgeStaleOlderThanQuantumCount = $null
$preAgeFutureCount = $null
$postCurrentTick = $null
$postLen = $null
$postTasks = @()
$postSummaryLen = $null
$postSummaryOverflow = $null
$postSummaryTimerCount = $null
$postSummaryInterruptCount = $null
$postSummaryManualCount = $null
$postSummaryNonzeroVectorCount = $null
$postSummaryStaleCount = $null
$postSummaryOldestTick = $null
$postSummaryNewestTick = $null
$postAgeCurrentTick = $null
$postAgeQuantumTicks = $null
$postAgeStaleCount = $null
$postAgeStaleOlderThanQuantumCount = $null
$postAgeFutureCount = $null
$finalQueueCount = $null
$finalStableTick = $null

if (Test-Path $gdbStdout) {
    $gdbOutput = [string](Get-Content -Path $gdbStdout -Raw)
    if ($null -eq $gdbOutput) { $gdbOutput = '' }
    $hitStart = $gdbOutput.Contains("HIT_START")
    $hitAfterWakeQueueSummaryAge = $gdbOutput.Contains("AFTER_WAKE_QUEUE_SUMMARY_AGE")
    $ack = Extract-IntValue -Text $gdbOutput -Name "ACK"
    $lastOpcode = Extract-IntValue -Text $gdbOutput -Name "LAST_OPCODE"
    $lastResult = Extract-IntValue -Text $gdbOutput -Name "LAST_RESULT"
    $ticks = Extract-IntValue -Text $gdbOutput -Name "TICKS"
    $mailboxOpcode = Extract-IntValue -Text $gdbOutput -Name "MAILBOX_OPCODE"
    $mailboxSeq = Extract-IntValue -Text $gdbOutput -Name "MAILBOX_SEQ"
    $preCurrentTick = Extract-IntValue -Text $gdbOutput -Name "PRE_CURRENT_TICK"
    $preLen = Extract-IntValue -Text $gdbOutput -Name "PRE_LEN"
    $preTasks = @(0, 1, 2, 3, 4 | ForEach-Object { Extract-IntValue -Text $gdbOutput -Name ("PRE_TASK{0}" -f $_) })
    $preReasons = @(0, 1, 2, 3, 4 | ForEach-Object { Extract-IntValue -Text $gdbOutput -Name ("PRE_REASON{0}" -f $_) })
    $preVectors = @(0, 1, 2, 3, 4 | ForEach-Object { Extract-IntValue -Text $gdbOutput -Name ("PRE_VECTOR{0}" -f $_) })
    $preTicks = @(0, 1, 2, 3, 4 | ForEach-Object { Extract-IntValue -Text $gdbOutput -Name ("PRE_TICK{0}" -f $_) })
    $preSummaryLen = Extract-IntValue -Text $gdbOutput -Name "PRE_SUMMARY_LEN"
    $preSummaryOverflow = Extract-IntValue -Text $gdbOutput -Name "PRE_SUMMARY_OVERFLOW"
    $preSummaryTimerCount = Extract-IntValue -Text $gdbOutput -Name "PRE_SUMMARY_TIMER_COUNT"
    $preSummaryInterruptCount = Extract-IntValue -Text $gdbOutput -Name "PRE_SUMMARY_INTERRUPT_COUNT"
    $preSummaryManualCount = Extract-IntValue -Text $gdbOutput -Name "PRE_SUMMARY_MANUAL_COUNT"
    $preSummaryNonzeroVectorCount = Extract-IntValue -Text $gdbOutput -Name "PRE_SUMMARY_NONZERO_VECTOR_COUNT"
    $preSummaryStaleCount = Extract-IntValue -Text $gdbOutput -Name "PRE_SUMMARY_STALE_COUNT"
    $preSummaryOldestTick = Extract-IntValue -Text $gdbOutput -Name "PRE_SUMMARY_OLDEST_TICK"
    $preSummaryNewestTick = Extract-IntValue -Text $gdbOutput -Name "PRE_SUMMARY_NEWEST_TICK"
    $preAgeCurrentTick = Extract-IntValue -Text $gdbOutput -Name "PRE_AGE_CURRENT_TICK"
    $preAgeQuantumTicks = Extract-IntValue -Text $gdbOutput -Name "PRE_AGE_QUANTUM_TICKS"
    $preAgeStaleCount = Extract-IntValue -Text $gdbOutput -Name "PRE_AGE_STALE_COUNT"
    $preAgeStaleOlderThanQuantumCount = Extract-IntValue -Text $gdbOutput -Name "PRE_AGE_STALE_OLDER_THAN_QUANTUM_COUNT"
    $preAgeFutureCount = Extract-IntValue -Text $gdbOutput -Name "PRE_AGE_FUTURE_COUNT"
    $postCurrentTick = Extract-IntValue -Text $gdbOutput -Name "POST_CURRENT_TICK"
    $postLen = Extract-IntValue -Text $gdbOutput -Name "POST_LEN"
    $postTasks = @(0, 1, 2, 3 | ForEach-Object { Extract-IntValue -Text $gdbOutput -Name ("POST_TASK{0}" -f $_) })
    $postSummaryLen = Extract-IntValue -Text $gdbOutput -Name "POST_SUMMARY_LEN"
    $postSummaryOverflow = Extract-IntValue -Text $gdbOutput -Name "POST_SUMMARY_OVERFLOW"
    $postSummaryTimerCount = Extract-IntValue -Text $gdbOutput -Name "POST_SUMMARY_TIMER_COUNT"
    $postSummaryInterruptCount = Extract-IntValue -Text $gdbOutput -Name "POST_SUMMARY_INTERRUPT_COUNT"
    $postSummaryManualCount = Extract-IntValue -Text $gdbOutput -Name "POST_SUMMARY_MANUAL_COUNT"
    $postSummaryNonzeroVectorCount = Extract-IntValue -Text $gdbOutput -Name "POST_SUMMARY_NONZERO_VECTOR_COUNT"
    $postSummaryStaleCount = Extract-IntValue -Text $gdbOutput -Name "POST_SUMMARY_STALE_COUNT"
    $postSummaryOldestTick = Extract-IntValue -Text $gdbOutput -Name "POST_SUMMARY_OLDEST_TICK"
    $postSummaryNewestTick = Extract-IntValue -Text $gdbOutput -Name "POST_SUMMARY_NEWEST_TICK"
    $postAgeCurrentTick = Extract-IntValue -Text $gdbOutput -Name "POST_AGE_CURRENT_TICK"
    $postAgeQuantumTicks = Extract-IntValue -Text $gdbOutput -Name "POST_AGE_QUANTUM_TICKS"
    $postAgeStaleCount = Extract-IntValue -Text $gdbOutput -Name "POST_AGE_STALE_COUNT"
    $postAgeStaleOlderThanQuantumCount = Extract-IntValue -Text $gdbOutput -Name "POST_AGE_STALE_OLDER_THAN_QUANTUM_COUNT"
    $postAgeFutureCount = Extract-IntValue -Text $gdbOutput -Name "POST_AGE_FUTURE_COUNT"
    $finalQueueCount = Extract-IntValue -Text $gdbOutput -Name "FINAL_QUEUE_COUNT"
    $finalStableTick = Extract-IntValue -Text $gdbOutput -Name "FINAL_STABLE_TICK"
}

$expectedPreTasks = @($taskIdTimer, $taskIdInterruptA1, $taskIdInterruptA2, $taskIdInterruptB, $taskIdManual)
$expectedPostTasks = @($taskIdTimer, $taskIdInterruptA2, $taskIdInterruptB, $taskIdManual)
$preThresholdTick = if ($preCurrentTick -lt $summaryAgeQuantum) { 0 } else { $preCurrentTick - $summaryAgeQuantum }
$postThresholdTick = if ($postCurrentTick -lt $summaryAgeQuantum) { 0 } else { $postCurrentTick - $summaryAgeQuantum }
$expectedPreTimerCount = @($preReasons | Where-Object { $_ -eq $wakeReasonTimer }).Count
$expectedPreInterruptCount = @($preReasons | Where-Object { $_ -eq $wakeReasonInterrupt }).Count
$expectedPreManualCount = @($preReasons | Where-Object { $_ -eq $wakeReasonManual }).Count
$expectedPreNonzeroVectorCount = @($preVectors | Where-Object { $_ -ne 0 }).Count
$expectedPreStaleCount = @($preTicks | Where-Object { $_ -le $preCurrentTick }).Count
$expectedPreOldStaleCount = @($preTicks | Where-Object { $_ -le $preThresholdTick }).Count
$expectedPreFutureCount = @($preTicks | Where-Object { $_ -gt $preCurrentTick }).Count
$expectedPreOldestTick = ($preTicks | Measure-Object -Minimum).Minimum
$expectedPreNewestTick = ($preTicks | Measure-Object -Maximum).Maximum
$postReasons = @($preReasons[0], $preReasons[2], $preReasons[3], $preReasons[4])
$postVectors = @($preVectors[0], $preVectors[2], $preVectors[3], $preVectors[4])
$postTicks = @($preTicks[0], $preTicks[2], $preTicks[3], $preTicks[4])
$expectedPostTimerCount = @($postReasons | Where-Object { $_ -eq $wakeReasonTimer }).Count
$expectedPostInterruptCount = @($postReasons | Where-Object { $_ -eq $wakeReasonInterrupt }).Count
$expectedPostManualCount = @($postReasons | Where-Object { $_ -eq $wakeReasonManual }).Count
$expectedPostNonzeroVectorCount = @($postVectors | Where-Object { $_ -ne 0 }).Count
$expectedPostStaleCount = @($postTicks | Where-Object { $_ -le $postCurrentTick }).Count
$expectedPostOldStaleCount = @($postTicks | Where-Object { $_ -le $postThresholdTick }).Count
$expectedPostFutureCount = @($postTicks | Where-Object { $_ -gt $postCurrentTick }).Count
$expectedPostOldestTick = ($postTicks | Measure-Object -Minimum).Minimum
$expectedPostNewestTick = ($postTicks | Measure-Object -Maximum).Maximum

Write-Output "BAREMETAL_QEMU_AVAILABLE=True"
Write-Output "BAREMETAL_QEMU_BINARY=$qemu"
Write-Output "BAREMETAL_GDB_BINARY=$gdb"
Write-Output "BAREMETAL_NM_BINARY=$nm"
Write-Output "BAREMETAL_QEMU_ARTIFACT=$artifact"
Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_START_ADDR=0x$startAddress"
Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_SPINPAUSE_ADDR=0x$spinPauseAddress"
Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_STATUS_ADDR=0x$statusAddress"
Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_MAILBOX_ADDR=0x$commandMailboxAddress"
Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_WAKE_QUEUE_ADDR=0x$wakeQueueAddress"
Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_WAKE_QUEUE_COUNT_ADDR=0x$wakeQueueCountAddress"
Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_SUMMARY_PTR_ADDR=0x$wakeQueueSummaryPtrAddress"
Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_AGE_PTR_ADDR=0x$wakeQueueAgeBucketsPtrAddress"
Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_AGE_PTR_QUANTUM_2_ADDR=0x$wakeQueueAgeBucketsPtrQuantum2Address"
Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_HIT_START=$hitStart"
Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_HIT_AFTER_SUMMARY_AGE=$hitAfterWakeQueueSummaryAge"
Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_GDB_STDOUT=$gdbStdout"
Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_GDB_STDERR=$gdbStderr"
Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_QEMU_STDOUT=$qemuStdout"
Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_QEMU_STDERR=$qemuStderr"
Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_TIMED_OUT=$timedOut"
Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_PRE_CURRENT_TICK=$preCurrentTick"
Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_PRE_LEN=$preLen"
for ($i = 0; $i -lt $preTasks.Count; $i++) {
    Write-Output ("BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_PRE_TASK{0}={1}" -f $i, $preTasks[$i])
}
Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_PRE_SUMMARY_LEN=$preSummaryLen"
Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_PRE_SUMMARY_OVERFLOW=$preSummaryOverflow"
Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_PRE_SUMMARY_TIMER_COUNT=$preSummaryTimerCount"
Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_PRE_SUMMARY_INTERRUPT_COUNT=$preSummaryInterruptCount"
Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_PRE_SUMMARY_MANUAL_COUNT=$preSummaryManualCount"
Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_PRE_SUMMARY_NONZERO_VECTOR_COUNT=$preSummaryNonzeroVectorCount"
Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_PRE_SUMMARY_STALE_COUNT=$preSummaryStaleCount"
Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_PRE_SUMMARY_OLDEST_TICK=$preSummaryOldestTick"
Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_PRE_SUMMARY_NEWEST_TICK=$preSummaryNewestTick"
Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_PRE_AGE_CURRENT_TICK=$preAgeCurrentTick"
Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_PRE_AGE_QUANTUM_TICKS=$preAgeQuantumTicks"
Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_PRE_AGE_STALE_COUNT=$preAgeStaleCount"
Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_PRE_AGE_STALE_OLDER_THAN_QUANTUM_COUNT=$preAgeStaleOlderThanQuantumCount"
Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_PRE_AGE_FUTURE_COUNT=$preAgeFutureCount"
Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_POST_CURRENT_TICK=$postCurrentTick"
Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_POST_LEN=$postLen"
for ($i = 0; $i -lt $postTasks.Count; $i++) {
    Write-Output ("BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_POST_TASK{0}={1}" -f $i, $postTasks[$i])
}
Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_POST_SUMMARY_LEN=$postSummaryLen"
Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_POST_SUMMARY_OVERFLOW=$postSummaryOverflow"
Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_POST_SUMMARY_TIMER_COUNT=$postSummaryTimerCount"
Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_POST_SUMMARY_INTERRUPT_COUNT=$postSummaryInterruptCount"
Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_POST_SUMMARY_MANUAL_COUNT=$postSummaryManualCount"
Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_POST_SUMMARY_NONZERO_VECTOR_COUNT=$postSummaryNonzeroVectorCount"
Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_POST_SUMMARY_STALE_COUNT=$postSummaryStaleCount"
Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_POST_SUMMARY_OLDEST_TICK=$postSummaryOldestTick"
Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_POST_SUMMARY_NEWEST_TICK=$postSummaryNewestTick"
Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_POST_AGE_CURRENT_TICK=$postAgeCurrentTick"
Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_POST_AGE_QUANTUM_TICKS=$postAgeQuantumTicks"
Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_POST_AGE_STALE_COUNT=$postAgeStaleCount"
Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_POST_AGE_STALE_OLDER_THAN_QUANTUM_COUNT=$postAgeStaleOlderThanQuantumCount"
Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_POST_AGE_FUTURE_COUNT=$postAgeFutureCount"
Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_FINAL_QUEUE_COUNT=$finalQueueCount"
Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_FINAL_STABLE_TICK=$finalStableTick"

$probePassed = $hitStart -and
    $hitAfterWakeQueueSummaryAge -and
    (-not $timedOut) -and
    ($ack -eq 20) -and
    ($lastOpcode -eq $wakeQueuePopReasonVectorOpcode) -and
    ($lastResult -eq 0) -and
    ($mailboxOpcode -eq $wakeQueuePopReasonVectorOpcode) -and
    ($mailboxSeq -eq 20) -and
    ($preLen -eq 5) -and
    ((@($preTasks) -join ',') -eq (@($expectedPreTasks) -join ',')) -and
    ($preSummaryLen -eq $preLen) -and
    ($preSummaryOverflow -eq 0) -and
    ($preSummaryTimerCount -eq $expectedPreTimerCount) -and
    ($preSummaryInterruptCount -eq $expectedPreInterruptCount) -and
    ($preSummaryManualCount -eq $expectedPreManualCount) -and
    ($preSummaryNonzeroVectorCount -eq $expectedPreNonzeroVectorCount) -and
    ($preSummaryStaleCount -eq $expectedPreStaleCount) -and
    ($preSummaryOldestTick -eq $expectedPreOldestTick) -and
    ($preSummaryNewestTick -eq $expectedPreNewestTick) -and
    ($preAgeCurrentTick -eq $preCurrentTick) -and
    ($preAgeQuantumTicks -eq $summaryAgeQuantum) -and
    ($preAgeStaleCount -eq $expectedPreStaleCount) -and
    ($preAgeStaleOlderThanQuantumCount -eq $expectedPreOldStaleCount) -and
    ($preAgeFutureCount -eq $expectedPreFutureCount) -and
    ($postLen -eq 4) -and
    ((@($postTasks) -join ',') -eq (@($expectedPostTasks) -join ',')) -and
    ($postSummaryLen -eq $postLen) -and
    ($postSummaryOverflow -eq 0) -and
    ($postSummaryTimerCount -eq $expectedPostTimerCount) -and
    ($postSummaryInterruptCount -eq $expectedPostInterruptCount) -and
    ($postSummaryManualCount -eq $expectedPostManualCount) -and
    ($postSummaryNonzeroVectorCount -eq $expectedPostNonzeroVectorCount) -and
    ($postSummaryStaleCount -eq $expectedPostStaleCount) -and
    ($postSummaryOldestTick -eq $expectedPostOldestTick) -and
    ($postSummaryNewestTick -eq $expectedPostNewestTick) -and
    ($postAgeCurrentTick -eq $postCurrentTick) -and
    ($postAgeQuantumTicks -eq $summaryAgeQuantum) -and
    ($postAgeStaleCount -eq $expectedPostStaleCount) -and
    ($postAgeStaleOlderThanQuantumCount -eq $expectedPostOldStaleCount) -and
    ($postAgeFutureCount -eq $expectedPostFutureCount) -and
    ($finalQueueCount -eq 4) -and
    ($finalStableTick -ge ($postCurrentTick + $postProbeSlackTicks))

Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE=$($(if ($probePassed) { 'pass' } else { 'fail' }))"

if (-not $probePassed) {
    if (Test-Path $gdbStderr) {
        Get-Content -Path $gdbStderr | Write-Error
    }
    exit 1
}
