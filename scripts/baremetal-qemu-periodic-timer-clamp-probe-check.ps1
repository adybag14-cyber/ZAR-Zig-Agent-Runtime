# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 60,
    [int] $GdbPort = 1274
)

$ErrorActionPreference = "Stop"

$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$releaseDir = Join-Path $repo "release"
$prerequisiteScript = Join-Path $PSScriptRoot "baremetal-qemu-periodic-timer-probe-check.ps1"
$artifact = Join-Path $releaseDir "openclaw-zig-baremetal-pvh-periodic-timer-probe.elf"
$gdbScript = Join-Path $releaseDir "qemu-periodic-timer-clamp-probe.gdb"
$gdbStdout = Join-Path $releaseDir "qemu-periodic-timer-clamp-probe.gdb.stdout.log"
$gdbStderr = Join-Path $releaseDir "qemu-periodic-timer-clamp-probe.gdb.stderr.log"
$qemuStdout = Join-Path $releaseDir "qemu-periodic-timer-clamp-probe.qemu.stdout.log"
$qemuStderr = Join-Path $releaseDir "qemu-periodic-timer-clamp-probe.qemu.stderr.log"

$schedulerResetOpcode = 26
$schedulerDisableOpcode = 25
$timerResetOpcode = 41
$wakeQueueClearOpcode = 44
$taskCreateOpcode = 27
$taskWaitOpcode = 50
$timerSchedulePeriodicOpcode = 49

$taskBudget = 8
$taskPriority = 1
$periodicDelay = 10
$nearMaxTick = 18446744073709551614
$maxTick = 18446744073709551615
$resultOk = 0
$modeRunning = 1
$taskStateReady = 1
$taskStateWaiting = 6
$timerEntryStateArmed = 1
$timerEntryFlagPeriodic = 1
$wakeReasonTimer = 1
$expectedFinalAck = 7

$statusModeOffset = 6
$statusTicksOffset = 8
$statusCommandSeqAckOffset = 28
$statusLastCommandOpcodeOffset = 32
$statusLastCommandResultOffset = 34
$statusTickBatchHintOffset = 36
$commandOpcodeOffset = 6
$commandSeqOffset = 8
$commandArg0Offset = 16
$commandArg1Offset = 24
$schedulerTaskCountOffset = 1
$taskIdOffset = 0
$taskStateOffset = 4
$timerEntryCountOffset = 1
$timerEntryPendingWakeCountOffset = 2
$timerEntryTimerIdOffset = 0
$timerEntryTaskIdOffset = 4
$timerEntryStateOffset = 8
$timerEntryFlagsOffset = 10
$timerEntryPeriodTicksOffset = 12
$timerEntryNextFireTickOffset = 16
$timerEntryFireCountOffset = 24
$timerEntryLastFireTickOffset = 32
$wakeEventStride = 32
$wakeEventSeqOffset = 0
$wakeEventTaskIdOffset = 4
$wakeEventTimerIdOffset = 8
$wakeEventReasonOffset = 12
$wakeEventVectorOffset = 13
$wakeEventTickOffset = 16

function Resolve-QemuExecutable {
    foreach ($name in @("qemu-system-x86_64", "qemu-system-x86_64.exe", "C:\Program Files\qemu\qemu-system-x86_64.exe")) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($null -ne $cmd -and $cmd.Path) { return $cmd.Path }
        if (Test-Path $name) { return (Resolve-Path $name).Path }
    }
    return $null
}

function Resolve-GdbExecutable {
    foreach ($name in @("gdb", "gdb.exe")) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($null -ne $cmd -and $cmd.Path) { return $cmd.Path }
    }
    return $null
}

function Resolve-NmExecutable {
    foreach ($name in @("llvm-nm", "llvm-nm.exe", "nm", "nm.exe", "C:\Users\Ady\Documents\starpro\tooling\emsdk\upstream\bin\llvm-nm.exe")) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($null -ne $cmd -and $cmd.Path) { return $cmd.Path }
        if (Test-Path $name) { return (Resolve-Path $name).Path }
    }
    return $null
}

function Resolve-SymbolAddress {
    param([string[]] $SymbolLines, [string] $Pattern, [string] $SymbolName)
    $line = $SymbolLines | Where-Object { $_ -match $Pattern } | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($line)) { throw "Failed to resolve symbol address for $SymbolName" }
    $parts = ($line.Trim() -split '\s+')
    if ($parts.Count -lt 3) { throw "Unexpected symbol line while resolving ${SymbolName}: $line" }
    return $parts[0]
}

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $pattern = '(?m)^' + [regex]::Escape($Name) + '=(-?\d+)$'
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { return $null }
    return [decimal]::Parse($match.Groups[1].Value)
}

function Invoke-PeriodicTimerArtifactBuildIfNeeded {
    if ($SkipBuild -and -not (Test-Path $artifact)) { throw "Periodic timer prerequisite artifact not found at $artifact and -SkipBuild was supplied." }
    if ($SkipBuild) { return }
    if (-not (Test-Path $prerequisiteScript)) { throw "Prerequisite script not found: $prerequisiteScript" }
    $prereqOutput = & $prerequisiteScript 2>&1
    $prereqExitCode = $LASTEXITCODE
    if ($prereqExitCode -ne 0) {
        if ($null -ne $prereqOutput) { $prereqOutput | Write-Output }
        throw "Periodic timer prerequisite failed with exit code $prereqExitCode"
    }
}

Set-Location $repo
New-Item -ItemType Directory -Force -Path $releaseDir | Out-Null

$qemu = Resolve-QemuExecutable
$gdb = Resolve-GdbExecutable
$nm = Resolve-NmExecutable

if ($null -eq $qemu) {
    Write-Output "BAREMETAL_QEMU_AVAILABLE=False"
    Write-Output "BAREMETAL_QEMU_PERIODIC_TIMER_CLAMP_PROBE=skipped"
    exit 0
}
if ($null -eq $gdb) {
    Write-Output "BAREMETAL_QEMU_AVAILABLE=True"
    Write-Output "BAREMETAL_QEMU_BINARY=$qemu"
    Write-Output "BAREMETAL_GDB_AVAILABLE=False"
    Write-Output "BAREMETAL_QEMU_PERIODIC_TIMER_CLAMP_PROBE=skipped"
    exit 0
}
if ($null -eq $nm) {
    Write-Output "BAREMETAL_QEMU_AVAILABLE=True"
    Write-Output "BAREMETAL_QEMU_BINARY=$qemu"
    Write-Output "BAREMETAL_GDB_BINARY=$gdb"
    Write-Output "BAREMETAL_NM_AVAILABLE=False"
    Write-Output "BAREMETAL_QEMU_PERIODIC_TIMER_CLAMP_PROBE=skipped"
    exit 0
}

if (-not (Test-Path $artifact)) {
    Invoke-PeriodicTimerArtifactBuildIfNeeded
} elseif (-not $SkipBuild) {
    Invoke-PeriodicTimerArtifactBuildIfNeeded
}

if (-not (Test-Path $artifact)) {
    Write-Output "BAREMETAL_QEMU_AVAILABLE=True"
    Write-Output "BAREMETAL_QEMU_BINARY=$qemu"
    Write-Output "BAREMETAL_GDB_BINARY=$gdb"
    Write-Output "BAREMETAL_NM_BINARY=$nm"
    Write-Output "BAREMETAL_QEMU_PERIODIC_TIMER_CLAMP_PROBE=skipped"
    exit 0
}

$symbolOutput = & $nm $artifact
if ($LASTEXITCODE -ne 0 -or $null -eq $symbolOutput -or $symbolOutput.Count -eq 0) {
    throw "Failed to resolve symbol table from $artifact using $nm"
}

$startAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[Tt]\s_start$' -SymbolName '_start'
$spinPauseAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[tT]\sbaremetal_main\.spinPause$' -SymbolName 'baremetal_main.spinPause'
$statusAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[dDbB]\sbaremetal_main\.status$' -SymbolName 'baremetal_main.status'
$commandMailboxAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[dDbB]\sbaremetal_main\.command_mailbox$' -SymbolName 'baremetal_main.command_mailbox'
$schedulerStateAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[dDbB]\sbaremetal_main\.scheduler_state$' -SymbolName 'baremetal_main.scheduler_state'
$schedulerTasksAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[dDbB]\sbaremetal_main\.scheduler_tasks$' -SymbolName 'baremetal_main.scheduler_tasks'
$timerStateAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[dDbB]\sbaremetal_main\.timer_state$' -SymbolName 'baremetal_main.timer_state'
$timerEntriesAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[dDbB]\sbaremetal_main\.timer_entries$' -SymbolName 'baremetal_main.timer_entries'
$wakeQueueAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[dDbB]\sbaremetal_main\.wake_queue$' -SymbolName 'baremetal_main.wake_queue'
$wakeQueueCountAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[dDbB]\sbaremetal_main\.wake_queue_count$' -SymbolName 'baremetal_main.wake_queue_count'
$artifactForGdb = $artifact.Replace('\', '/')

@"
set pagination off
set confirm off
set `$_stage = 0
set `$_expected_seq = 0
set `$_task_id = 0
set `$_pre_schedule_ticks = 0
set `$_armed_ticks = 0
set `$_armed_timer_id = 0
set `$_armed_next_fire = 0
set `$_armed_state = 0
set `$_armed_flags = 0
set `$_fire_ticks = 0
set `$_fire_count = 0
set `$_fire_last_tick = 0
set `$_fire_next_fire = 0
set `$_fire_state = 0
set `$_fire_pending_wakes = 0
set `$_wake_count = 0
set `$_wake0_seq = 0
set `$_wake0_task_id = 0
set `$_wake0_timer_id = 0
set `$_wake0_reason = 0
set `$_wake0_vector = 0
set `$_wake0_tick = 0
set `$_hold_ticks = 0
set `$_hold_fire_count = 0
set `$_hold_wake_count = 0
set `$_hold_next_fire = 0
set `$_hold_task_state = 0
file $artifactForGdb
handle SIGQUIT nostop noprint pass
target remote :$GdbPort
break *0x$startAddress
commands
silent
printf "HIT_START\n"
continue
end
break *0x$spinPauseAddress
commands
silent
if `$_stage == 0
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == 0
    set *(unsigned char*)(0x$statusAddress+$statusModeOffset) = $modeRunning
    set *(unsigned long long*)(0x$statusAddress+$statusTicksOffset) = 0
    set *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) = 0
    set *(unsigned short*)(0x$statusAddress+$statusLastCommandOpcodeOffset) = 0
    set *(short*)(0x$statusAddress+$statusLastCommandResultOffset) = 0
    set *(unsigned int*)(0x$statusAddress+$statusTickBatchHintOffset) = 1
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $schedulerResetOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = 1
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = 0
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = 0
    set `$_expected_seq = 1
    set `$_stage = 1
  end
  continue
end
if `$_stage == 1
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == `$_expected_seq && *(unsigned char*)(0x$schedulerStateAddress+$schedulerTaskCountOffset) == 0
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $timerResetOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = (`$_expected_seq + 1)
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = 0
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = 0
    set `$_expected_seq = (`$_expected_seq + 1)
    set `$_stage = 2
  end
  continue
end
if `$_stage == 2
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == `$_expected_seq && *(unsigned char*)(0x$timerStateAddress+$timerEntryCountOffset) == 0
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $wakeQueueClearOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = (`$_expected_seq + 1)
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = 0
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = 0
    set `$_expected_seq = (`$_expected_seq + 1)
    set `$_stage = 3
  end
  continue
end
if `$_stage == 3
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == `$_expected_seq && *(unsigned int*)0x$wakeQueueCountAddress == 0
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $schedulerDisableOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = (`$_expected_seq + 1)
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = 0
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = 0
    set `$_expected_seq = (`$_expected_seq + 1)
    set `$_stage = 4
  end
  continue
end
if `$_stage == 4
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == `$_expected_seq && *(unsigned char*)(0x$schedulerStateAddress+$schedulerTaskCountOffset) == 0
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $taskCreateOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = (`$_expected_seq + 1)
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = $taskBudget
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = $taskPriority
    set `$_expected_seq = (`$_expected_seq + 1)
    set `$_stage = 5
  end
  continue
end
if `$_stage == 5
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == `$_expected_seq && *(unsigned int*)(0x$schedulerTasksAddress+$taskIdOffset) != 0
    set `$_task_id = *(unsigned int*)(0x$schedulerTasksAddress+$taskIdOffset)
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $taskWaitOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = (`$_expected_seq + 1)
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = `$_task_id
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = 0
    set `$_expected_seq = (`$_expected_seq + 1)
    set `$_stage = 6
  end
  continue
end
if `$_stage == 6
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == `$_expected_seq && *(unsigned char*)(0x$schedulerTasksAddress+$taskStateOffset) == $taskStateWaiting
    set *(unsigned long long*)(0x$statusAddress+$statusTicksOffset) = $nearMaxTick
    set `$_pre_schedule_ticks = *(unsigned long long*)(0x$statusAddress+$statusTicksOffset)
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $timerSchedulePeriodicOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = (`$_expected_seq + 1)
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = `$_task_id
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = $periodicDelay
    set `$_expected_seq = (`$_expected_seq + 1)
    set `$_stage = 7
  end
  continue
end
if `$_stage == 7
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == `$_expected_seq && *(unsigned char*)(0x$timerStateAddress+$timerEntryCountOffset) == 1 && *(unsigned long long*)(0x$timerEntriesAddress+$timerEntryNextFireTickOffset) == $maxTick && *(unsigned int*)(0x$timerEntriesAddress+$timerEntryPeriodTicksOffset) == $periodicDelay && *(unsigned char*)(0x$timerEntriesAddress+$timerEntryStateOffset) == $timerEntryStateArmed && *(unsigned long long*)(0x$statusAddress+$statusTicksOffset) == $maxTick
    set `$_armed_ticks = *(unsigned long long*)(0x$statusAddress+$statusTicksOffset)
    set `$_armed_timer_id = *(unsigned int*)(0x$timerEntriesAddress+$timerEntryTimerIdOffset)
    set `$_armed_next_fire = *(unsigned long long*)(0x$timerEntriesAddress+$timerEntryNextFireTickOffset)
    set `$_armed_state = *(unsigned char*)(0x$timerEntriesAddress+$timerEntryStateOffset)
    set `$_armed_flags = *(unsigned short*)(0x$timerEntriesAddress+$timerEntryFlagsOffset)
    set `$_stage = 8
  end
  continue
end
if `$_stage == 8
  if *(unsigned long long*)(0x$statusAddress+$statusTicksOffset) == 0 && *(unsigned int*)0x$wakeQueueCountAddress == 1 && *(unsigned int*)(0x$timerEntriesAddress+$timerEntryFireCountOffset) == 1 && *(unsigned long long*)(0x$timerEntriesAddress+$timerEntryLastFireTickOffset) == $maxTick && *(unsigned long long*)(0x$timerEntriesAddress+$timerEntryNextFireTickOffset) == $maxTick && *(unsigned char*)(0x$schedulerTasksAddress+$taskStateOffset) == $taskStateReady
    set `$_fire_ticks = *(unsigned long long*)(0x$statusAddress+$statusTicksOffset)
    set `$_fire_count = *(unsigned int*)(0x$timerEntriesAddress+$timerEntryFireCountOffset)
    set `$_fire_last_tick = *(unsigned long long*)(0x$timerEntriesAddress+$timerEntryLastFireTickOffset)
    set `$_fire_next_fire = *(unsigned long long*)(0x$timerEntriesAddress+$timerEntryNextFireTickOffset)
    set `$_fire_state = *(unsigned char*)(0x$timerEntriesAddress+$timerEntryStateOffset)
    set `$_fire_pending_wakes = *(unsigned short*)(0x$timerStateAddress+$timerEntryPendingWakeCountOffset)
    set `$_wake_count = *(unsigned int*)0x$wakeQueueCountAddress
    set `$_wake0_seq = *(unsigned int*)(0x$wakeQueueAddress+$wakeEventSeqOffset)
    set `$_wake0_task_id = *(unsigned int*)(0x$wakeQueueAddress+$wakeEventTaskIdOffset)
    set `$_wake0_timer_id = *(unsigned int*)(0x$wakeQueueAddress+$wakeEventTimerIdOffset)
    set `$_wake0_reason = *(unsigned char*)(0x$wakeQueueAddress+$wakeEventReasonOffset)
    set `$_wake0_vector = *(unsigned char*)(0x$wakeQueueAddress+$wakeEventVectorOffset)
    set `$_wake0_tick = *(unsigned long long*)(0x$wakeQueueAddress+$wakeEventTickOffset)
    set `$_stage = 9
  end
  continue
end
if `$_stage == 9
  if *(unsigned long long*)(0x$statusAddress+$statusTicksOffset) >= 1 && *(unsigned int*)0x$wakeQueueCountAddress == 1 && *(unsigned int*)(0x$timerEntriesAddress+$timerEntryFireCountOffset) == 1 && *(unsigned long long*)(0x$timerEntriesAddress+$timerEntryNextFireTickOffset) == $maxTick && *(unsigned char*)(0x$schedulerTasksAddress+$taskStateOffset) == $taskStateReady
    set `$_hold_ticks = *(unsigned long long*)(0x$statusAddress+$statusTicksOffset)
    set `$_hold_fire_count = *(unsigned int*)(0x$timerEntriesAddress+$timerEntryFireCountOffset)
    set `$_hold_wake_count = *(unsigned int*)0x$wakeQueueCountAddress
    set `$_hold_next_fire = *(unsigned long long*)(0x$timerEntriesAddress+$timerEntryNextFireTickOffset)
    set `$_hold_task_state = *(unsigned char*)(0x$schedulerTasksAddress+$taskStateOffset)
    printf "AFTER_PERIODIC_TIMER_CLAMP\n"
    printf "ACK=%u\n", *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset)
    printf "LAST_OPCODE=%u\n", *(unsigned short*)(0x$statusAddress+$statusLastCommandOpcodeOffset)
    printf "LAST_RESULT=%d\n", *(short*)(0x$statusAddress+$statusLastCommandResultOffset)
    printf "TASK_ID=%u\n", `$_task_id
    printf "PRE_SCHEDULE_TICKS=%llu\n", `$_pre_schedule_ticks
    printf "ARM_TICKS=%llu\n", `$_armed_ticks
    printf "ARM_TIMER_ID=%u\n", `$_armed_timer_id
    printf "ARM_NEXT_FIRE=%llu\n", `$_armed_next_fire
    printf "ARM_STATE=%u\n", `$_armed_state
    printf "ARM_FLAGS=%u\n", `$_armed_flags
    printf "FIRE_TICKS=%llu\n", `$_fire_ticks
    printf "FIRE_COUNT=%u\n", `$_fire_count
    printf "FIRE_LAST_TICK=%llu\n", `$_fire_last_tick
    printf "FIRE_NEXT_FIRE=%llu\n", `$_fire_next_fire
    printf "FIRE_STATE=%u\n", `$_fire_state
    printf "FIRE_PENDING_WAKES=%u\n", `$_fire_pending_wakes
    printf "WAKE_COUNT=%u\n", `$_wake_count
    printf "WAKE0_SEQ=%u\n", `$_wake0_seq
    printf "WAKE0_TASK_ID=%u\n", `$_wake0_task_id
    printf "WAKE0_TIMER_ID=%u\n", `$_wake0_timer_id
    printf "WAKE0_REASON=%u\n", `$_wake0_reason
    printf "WAKE0_VECTOR=%u\n", `$_wake0_vector
    printf "WAKE0_TICK=%llu\n", `$_wake0_tick
    printf "HOLD_TICKS=%llu\n", `$_hold_ticks
    printf "HOLD_FIRE_COUNT=%u\n", `$_hold_fire_count
    printf "HOLD_WAKE_COUNT=%u\n", `$_hold_wake_count
    printf "HOLD_NEXT_FIRE=%llu\n", `$_hold_next_fire
    printf "HOLD_TASK_STATE=%u\n", `$_hold_task_state
    quit
  end
  continue
end
continue
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

$qemuProc = $null
$gdbProc = $null
$timedOut = $false

try {
    $qemuProc = Start-Process -FilePath $qemu -ArgumentList $qemuArgs -PassThru -NoNewWindow -RedirectStandardOutput $qemuStdout -RedirectStandardError $qemuStderr
    Start-Sleep -Milliseconds 700

    $gdbArgs = @(
        "-q",
        "-batch",
        "-x", $gdbScript
    )

    $gdbProc = Start-Process -FilePath $gdb -ArgumentList $gdbArgs -PassThru -NoNewWindow -RedirectStandardOutput $gdbStdout -RedirectStandardError $gdbStderr
    $null = Wait-Process -Id $gdbProc.Id -Timeout $TimeoutSeconds -ErrorAction Stop
}
catch {
    $timedOut = $true
    if ($null -ne $gdbProc) {
        try { Stop-Process -Id $gdbProc.Id -Force -ErrorAction SilentlyContinue } catch {}
    }
}
finally {
    if ($null -ne $qemuProc) {
        try { Stop-Process -Id $qemuProc.Id -Force -ErrorAction SilentlyContinue } catch {}
    }
}

$gdbOutput = ""
$gdbError = ""
$hitStart = $false
$hitAfter = $false
if (Test-Path $gdbStdout) {
    $gdbOutput = [string](Get-Content -Path $gdbStdout -Raw)
    if ($null -eq $gdbOutput) { $gdbOutput = "" }
    $hitStart = $gdbOutput.Contains("HIT_START")
    $hitAfter = $gdbOutput.Contains("AFTER_PERIODIC_TIMER_CLAMP")
}
if (Test-Path $gdbStderr) {
    $gdbError = [string](Get-Content -Path $gdbStderr -Raw)
    if ($null -eq $gdbError) { $gdbError = "" }
}

if ($timedOut) { throw "QEMU periodic timer clamp probe timed out after $TimeoutSeconds seconds.`nSTDOUT:`n$gdbOutput`nSTDERR:`n$gdbError" }
$gdbExitCode = if ($null -eq $gdbProc -or $null -eq $gdbProc.ExitCode) { 0 } else { [int] $gdbProc.ExitCode }
if ($gdbExitCode -ne 0) { throw "gdb exited with code $gdbExitCode.`nSTDOUT:`n$gdbOutput`nSTDERR:`n$gdbError" }
if (-not $hitStart -or -not $hitAfter) { throw "Periodic timer clamp probe did not reach expected checkpoints.`nSTDOUT:`n$gdbOutput`nSTDERR:`n$gdbError" }

$ack = Extract-IntValue -Text $gdbOutput -Name "ACK"
$lastOpcode = Extract-IntValue -Text $gdbOutput -Name "LAST_OPCODE"
$lastResult = Extract-IntValue -Text $gdbOutput -Name "LAST_RESULT"
$taskId = Extract-IntValue -Text $gdbOutput -Name "TASK_ID"
$preScheduleTicks = Extract-IntValue -Text $gdbOutput -Name "PRE_SCHEDULE_TICKS"
$armTicks = Extract-IntValue -Text $gdbOutput -Name "ARM_TICKS"
$armTimerId = Extract-IntValue -Text $gdbOutput -Name "ARM_TIMER_ID"
$armNextFire = Extract-IntValue -Text $gdbOutput -Name "ARM_NEXT_FIRE"
$armState = Extract-IntValue -Text $gdbOutput -Name "ARM_STATE"
$armFlags = Extract-IntValue -Text $gdbOutput -Name "ARM_FLAGS"
$fireTicks = Extract-IntValue -Text $gdbOutput -Name "FIRE_TICKS"
$fireCount = Extract-IntValue -Text $gdbOutput -Name "FIRE_COUNT"
$fireLastTick = Extract-IntValue -Text $gdbOutput -Name "FIRE_LAST_TICK"
$fireNextFire = Extract-IntValue -Text $gdbOutput -Name "FIRE_NEXT_FIRE"
$fireState = Extract-IntValue -Text $gdbOutput -Name "FIRE_STATE"
$firePendingWakes = Extract-IntValue -Text $gdbOutput -Name "FIRE_PENDING_WAKES"
$wakeCount = Extract-IntValue -Text $gdbOutput -Name "WAKE_COUNT"
$wake0Seq = Extract-IntValue -Text $gdbOutput -Name "WAKE0_SEQ"
$wake0TaskId = Extract-IntValue -Text $gdbOutput -Name "WAKE0_TASK_ID"
$wake0TimerId = Extract-IntValue -Text $gdbOutput -Name "WAKE0_TIMER_ID"
$wake0Reason = Extract-IntValue -Text $gdbOutput -Name "WAKE0_REASON"
$wake0Vector = Extract-IntValue -Text $gdbOutput -Name "WAKE0_VECTOR"
$wake0Tick = Extract-IntValue -Text $gdbOutput -Name "WAKE0_TICK"
$holdTicks = Extract-IntValue -Text $gdbOutput -Name "HOLD_TICKS"
$holdFireCount = Extract-IntValue -Text $gdbOutput -Name "HOLD_FIRE_COUNT"
$holdWakeCount = Extract-IntValue -Text $gdbOutput -Name "HOLD_WAKE_COUNT"
$holdNextFire = Extract-IntValue -Text $gdbOutput -Name "HOLD_NEXT_FIRE"
$holdTaskState = Extract-IntValue -Text $gdbOutput -Name "HOLD_TASK_STATE"

if ($ack -ne $expectedFinalAck) { throw "Expected ACK=$expectedFinalAck, got $ack" }
if ($lastOpcode -ne $timerSchedulePeriodicOpcode) { throw "Expected LAST_OPCODE=$timerSchedulePeriodicOpcode, got $lastOpcode" }
if ($lastResult -ne $resultOk) { throw "Expected LAST_RESULT=$resultOk, got $lastResult" }
if ($taskId -ne 1) { throw "Expected TASK_ID=1, got $taskId" }
if ($preScheduleTicks -ne $nearMaxTick) { throw "Expected PRE_SCHEDULE_TICKS=$nearMaxTick, got $preScheduleTicks" }
if ($armTicks -ne $maxTick) { throw "Expected ARM_TICKS=$maxTick, got $armTicks" }
if ($armTimerId -ne 1) { throw "Expected ARM_TIMER_ID=1, got $armTimerId" }
if ($armNextFire -ne $maxTick) { throw "Expected ARM_NEXT_FIRE=$maxTick, got $armNextFire" }
if ($armState -ne $timerEntryStateArmed) { throw "Expected ARM_STATE=$timerEntryStateArmed, got $armState" }
if (($armFlags -band $timerEntryFlagPeriodic) -ne $timerEntryFlagPeriodic) { throw "Expected ARM_FLAGS to include periodic flag, got $armFlags" }
if ($fireTicks -ne 0) { throw "Expected FIRE_TICKS=0 after wrap, got $fireTicks" }
if ($fireCount -ne 1) { throw "Expected FIRE_COUNT=1, got $fireCount" }
if ($fireLastTick -ne $maxTick) { throw "Expected FIRE_LAST_TICK=$maxTick, got $fireLastTick" }
if ($fireNextFire -ne $maxTick) { throw "Expected FIRE_NEXT_FIRE=$maxTick, got $fireNextFire" }
if ($fireState -ne $timerEntryStateArmed) { throw "Expected FIRE_STATE=$timerEntryStateArmed, got $fireState" }
if ($firePendingWakes -ne 1) { throw "Expected FIRE_PENDING_WAKES=1, got $firePendingWakes" }
if ($wakeCount -ne 1) { throw "Expected WAKE_COUNT=1, got $wakeCount" }
if ($wake0Seq -ne 1) { throw "Expected WAKE0_SEQ=1, got $wake0Seq" }
if ($wake0TaskId -ne 1) { throw "Expected WAKE0_TASK_ID=1, got $wake0TaskId" }
if ($wake0TimerId -ne 1) { throw "Expected WAKE0_TIMER_ID=1, got $wake0TimerId" }
if ($wake0Reason -ne $wakeReasonTimer) { throw "Expected WAKE0_REASON=$wakeReasonTimer, got $wake0Reason" }
if ($wake0Vector -ne 0) { throw "Expected WAKE0_VECTOR=0, got $wake0Vector" }
if ($wake0Tick -ne $maxTick) { throw "Expected WAKE0_TICK=$maxTick, got $wake0Tick" }
if ($holdTicks -lt 1) { throw "Expected HOLD_TICKS >= 1, got $holdTicks" }
if ($holdFireCount -ne 1) { throw "Expected HOLD_FIRE_COUNT=1, got $holdFireCount" }
if ($holdWakeCount -ne 1) { throw "Expected HOLD_WAKE_COUNT=1, got $holdWakeCount" }
if ($holdNextFire -ne $maxTick) { throw "Expected HOLD_NEXT_FIRE=$maxTick, got $holdNextFire" }
if ($holdTaskState -ne $taskStateReady) { throw "Expected HOLD_TASK_STATE=$taskStateReady, got $holdTaskState" }

Write-Output "BAREMETAL_QEMU_AVAILABLE=True"
Write-Output "BAREMETAL_QEMU_BINARY=$qemu"
Write-Output "BAREMETAL_GDB_BINARY=$gdb"
Write-Output "BAREMETAL_NM_BINARY=$nm"
Write-Output "BAREMETAL_QEMU_PERIODIC_TIMER_CLAMP_PROBE=pass"
Write-Output "ACK=$ack"
Write-Output "LAST_OPCODE=$lastOpcode"
Write-Output "LAST_RESULT=$lastResult"
Write-Output "TASK_ID=$taskId"
Write-Output "PRE_SCHEDULE_TICKS=$preScheduleTicks"
Write-Output "ARM_TICKS=$armTicks"
Write-Output "ARM_TIMER_ID=$armTimerId"
Write-Output "ARM_NEXT_FIRE=$armNextFire"
Write-Output "ARM_STATE=$armState"
Write-Output "ARM_FLAGS=$armFlags"
Write-Output "FIRE_TICKS=$fireTicks"
Write-Output "FIRE_COUNT=$fireCount"
Write-Output "FIRE_LAST_TICK=$fireLastTick"
Write-Output "FIRE_NEXT_FIRE=$fireNextFire"
Write-Output "FIRE_STATE=$fireState"
Write-Output "FIRE_PENDING_WAKES=$firePendingWakes"
Write-Output "WAKE_COUNT=$wakeCount"
Write-Output "WAKE0_SEQ=$wake0Seq"
Write-Output "WAKE0_TASK_ID=$wake0TaskId"
Write-Output "WAKE0_TIMER_ID=$wake0TimerId"
Write-Output "WAKE0_REASON=$wake0Reason"
Write-Output "WAKE0_VECTOR=$wake0Vector"
Write-Output "WAKE0_TICK=$wake0Tick"
Write-Output "HOLD_TICKS=$holdTicks"
Write-Output "HOLD_FIRE_COUNT=$holdFireCount"
Write-Output "HOLD_WAKE_COUNT=$holdWakeCount"
Write-Output "HOLD_NEXT_FIRE=$holdNextFire"
Write-Output "HOLD_TASK_STATE=$holdTaskState"
