param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 90,
    [int] $GdbPort = 1259
)

$ErrorActionPreference = "Stop"

$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$releaseDir = Join-Path $repo "release"
$prerequisiteScript = Join-Path $PSScriptRoot "baremetal-qemu-wake-queue-batch-pop-probe-check.ps1"
$artifact = Join-Path $releaseDir "openclaw-zig-baremetal-pvh-wake-queue-batch-pop.elf"
$gdbScript = Join-Path $releaseDir "qemu-wake-queue-before-tick-overflow-probe.gdb"
$gdbStdout = Join-Path $releaseDir "qemu-wake-queue-before-tick-overflow-probe.gdb.stdout.log"
$gdbStderr = Join-Path $releaseDir "qemu-wake-queue-before-tick-overflow-probe.gdb.stderr.log"
$qemuStdout = Join-Path $releaseDir "qemu-wake-queue-before-tick-overflow-probe.qemu.stdout.log"
$qemuStderr = Join-Path $releaseDir "qemu-wake-queue-before-tick-overflow-probe.qemu.stderr.log"

$schedulerResetOpcode = 26
$wakeQueueClearOpcode = 44
$resetInterruptCountersOpcode = 8
$schedulerDisableOpcode = 25
$taskCreateOpcode = 27
$taskWaitInterruptOpcode = 57
$triggerInterruptOpcode = 7
$wakeQueuePopBeforeTickOpcode = 61

$taskBudget = 5
$expectedTaskPriority = 0
$wakeQueueCapacity = 64
$overflowCycles = 66
$expectedOverflow = 2
$vectorA = 13
$vectorB = 31
$waitInterruptAnyVector = 65535
$resultOk = 0
$resultNotFound = -2
$modeRunning = 1
$taskStateReady = 1
$taskStateWaiting = 6
$expectedFinalAck = 141
$expectedFinalTickFloor = 141

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
$wakeEventStride = 32
$wakeEventSeqOffset = 0
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
    return [int64]::Parse($match.Groups[1].Value)
}

function Invoke-BatchPopArtifactBuildIfNeeded {
    if ($SkipBuild -and -not (Test-Path $artifact)) { throw "Wake-queue before-tick overflow prerequisite artifact not found at $artifact and -SkipBuild was supplied." }
    if ($SkipBuild) { return }
    if (-not (Test-Path $prerequisiteScript)) { throw "Prerequisite script not found: $prerequisiteScript" }
    $prereqOutput = & $prerequisiteScript 2>&1
    $prereqExitCode = $LASTEXITCODE
    if ($prereqExitCode -ne 0) {
        if ($null -ne $prereqOutput) { $prereqOutput | Write-Output }
        throw "Wake-queue batch-pop prerequisite failed with exit code $prereqExitCode"
    }
}

Set-Location $repo
New-Item -ItemType Directory -Force -Path $releaseDir | Out-Null

$qemu = Resolve-QemuExecutable
$gdb = Resolve-GdbExecutable
$nm = Resolve-NmExecutable

if ($null -eq $qemu) {
    Write-Output "BAREMETAL_QEMU_AVAILABLE=False"
    Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_OVERFLOW_PROBE=skipped"
    exit 0
}
if ($null -eq $gdb) {
    Write-Output "BAREMETAL_QEMU_AVAILABLE=True"
    Write-Output "BAREMETAL_QEMU_BINARY=$qemu"
    Write-Output "BAREMETAL_GDB_AVAILABLE=False"
    Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_OVERFLOW_PROBE=skipped"
    exit 0
}
if ($null -eq $nm) {
    Write-Output "BAREMETAL_QEMU_AVAILABLE=True"
    Write-Output "BAREMETAL_QEMU_BINARY=$qemu"
    Write-Output "BAREMETAL_GDB_BINARY=$gdb"
    Write-Output "BAREMETAL_NM_AVAILABLE=False"
    Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_OVERFLOW_PROBE=skipped"
    exit 0
}

if (-not (Test-Path $artifact)) {
    Invoke-BatchPopArtifactBuildIfNeeded
} elseif (-not $SkipBuild) {
    Invoke-BatchPopArtifactBuildIfNeeded
}

if (-not (Test-Path $artifact)) {
    Write-Output "BAREMETAL_QEMU_AVAILABLE=True"
    Write-Output "BAREMETAL_QEMU_BINARY=$qemu"
    Write-Output "BAREMETAL_GDB_BINARY=$gdb"
    Write-Output "BAREMETAL_NM_BINARY=$nm"
    Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_OVERFLOW_PROBE=skipped"
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
$wakeQueueAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[dDbB]\sbaremetal_main\.wake_queue$' -SymbolName 'baremetal_main.wake_queue'
$wakeQueueCountAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[dDbB]\sbaremetal_main\.wake_queue_count$' -SymbolName 'baremetal_main.wake_queue_count'
$wakeQueueHeadAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[dDbB]\sbaremetal_main\.wake_queue_head$' -SymbolName 'baremetal_main.wake_queue_head'
$wakeQueueTailAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[dDbB]\sbaremetal_main\.wake_queue_tail$' -SymbolName 'baremetal_main.wake_queue_tail'
$wakeQueueOverflowAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[dDbB]\sbaremetal_main\.wake_queue_overflow$' -SymbolName 'baremetal_main.wake_queue_overflow'
$artifactForGdb = $artifact.Replace('\', '/')

@"
set pagination off
set confirm off
set `$_stage = 0
set `$_expected_seq = 0
set `$_task_id = 0
set `$_wake_cycles = 0
set `$_current_vector = 0
set `$_pre_count = 0
set `$_pre_head = 0
set `$_pre_tail = 0
set `$_pre_overflow = 0
set `$_pre_first_seq = 0
set `$_pre_first_tick = 0
set `$_pre_cutoff_seq = 0
set `$_pre_cutoff_tick = 0
set `$_pre_last_seq = 0
set `$_pre_last_tick = 0
set `$_post_first_count = 0
set `$_post_first_head = 0
set `$_post_first_tail = 0
set `$_post_first_overflow = 0
set `$_post_first_seq = 0
set `$_post_first_tick = 0
set `$_post_first_cutoff_seq = 0
set `$_post_first_cutoff_tick = 0
set `$_post_first_last_seq = 0
set `$_post_first_last_tick = 0
set `$_post_second_count = 0
set `$_post_second_head = 0
set `$_post_second_tail = 0
set `$_post_second_overflow = 0
set `$_post_second_seq = 0
set `$_post_second_tick = 0
set `$_final_count = 0
set `$_final_head = 0
set `$_final_tail = 0
set `$_final_overflow = 0
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
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $wakeQueueClearOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = (`$_expected_seq + 1)
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = 0
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = 0
    set `$_expected_seq = (`$_expected_seq + 1)
    set `$_stage = 2
  end
  continue
end
if `$_stage == 2
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == `$_expected_seq && *(unsigned int*)0x$wakeQueueCountAddress == 0
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $resetInterruptCountersOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = (`$_expected_seq + 1)
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = 0
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = 0
    set `$_expected_seq = (`$_expected_seq + 1)
    set `$_stage = 3
  end
  continue
end
if `$_stage == 3
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == `$_expected_seq
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
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = $expectedTaskPriority
    set `$_expected_seq = (`$_expected_seq + 1)
    set `$_stage = 5
  end
  continue
end
if `$_stage == 5
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == `$_expected_seq && *(unsigned int*)(0x$schedulerTasksAddress+$taskIdOffset) != 0
    set `$_task_id = *(unsigned int*)(0x$schedulerTasksAddress+$taskIdOffset)
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $taskWaitInterruptOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = (`$_expected_seq + 1)
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = `$_task_id
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = $waitInterruptAnyVector
    set `$_expected_seq = (`$_expected_seq + 1)
    set `$_stage = 6
  end
  continue
end
if `$_stage == 6
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == `$_expected_seq && *(unsigned char*)(0x$schedulerTasksAddress+$taskStateOffset) == $taskStateWaiting
    if (`$_wake_cycles & 1) == 0
      set `$_current_vector = $vectorA
    else
      set `$_current_vector = $vectorB
    end
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $triggerInterruptOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = (`$_expected_seq + 1)
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = `$_current_vector
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = 0
    set `$_expected_seq = (`$_expected_seq + 1)
    set `$_stage = 7
  end
  continue
end
if `$_stage == 7
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == `$_expected_seq && *(unsigned char*)(0x$schedulerTasksAddress+$taskStateOffset) == $taskStateReady
    set `$_wake_cycles = (`$_wake_cycles + 1)
    if `$_wake_cycles == $overflowCycles && *(unsigned int*)0x$wakeQueueCountAddress == $wakeQueueCapacity && *(unsigned int*)0x$wakeQueueOverflowAddress == $expectedOverflow
      set `$_pre_count = *(unsigned int*)0x$wakeQueueCountAddress
      set `$_pre_head = *(unsigned int*)0x$wakeQueueHeadAddress
      set `$_pre_tail = *(unsigned int*)0x$wakeQueueTailAddress
      set `$_pre_overflow = *(unsigned int*)0x$wakeQueueOverflowAddress
      set `$_pre_first_seq = *(unsigned int*)(0x$wakeQueueAddress + (2 * $wakeEventStride) + $wakeEventSeqOffset)
      set `$_pre_first_tick = *(unsigned long long*)(0x$wakeQueueAddress + (2 * $wakeEventStride) + $wakeEventTickOffset)
      set `$_pre_cutoff_seq = *(unsigned int*)(0x$wakeQueueAddress + (33 * $wakeEventStride) + $wakeEventSeqOffset)
      set `$_pre_cutoff_tick = *(unsigned long long*)(0x$wakeQueueAddress + (33 * $wakeEventStride) + $wakeEventTickOffset)
      set `$_pre_last_seq = *(unsigned int*)(0x$wakeQueueAddress + (1 * $wakeEventStride) + $wakeEventSeqOffset)
      set `$_pre_last_tick = *(unsigned long long*)(0x$wakeQueueAddress + (1 * $wakeEventStride) + $wakeEventTickOffset)
      set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $wakeQueuePopBeforeTickOpcode
      set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = (`$_expected_seq + 1)
      set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = `$_pre_cutoff_tick
      set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = 99
      set `$_expected_seq = (`$_expected_seq + 1)
      set `$_stage = 8
    else
      set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $taskWaitInterruptOpcode
      set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = (`$_expected_seq + 1)
      set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = `$_task_id
      set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = $waitInterruptAnyVector
      set `$_expected_seq = (`$_expected_seq + 1)
      set `$_stage = 6
    end
  end
  continue
end
if `$_stage == 8
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == `$_expected_seq && *(unsigned int*)0x$wakeQueueCountAddress == 32 && *(unsigned int*)0x$wakeQueueHeadAddress == 32 && *(unsigned int*)0x$wakeQueueTailAddress == 0
    set `$_post_first_count = *(unsigned int*)0x$wakeQueueCountAddress
    set `$_post_first_head = *(unsigned int*)0x$wakeQueueHeadAddress
    set `$_post_first_tail = *(unsigned int*)0x$wakeQueueTailAddress
    set `$_post_first_overflow = *(unsigned int*)0x$wakeQueueOverflowAddress
    set `$_post_first_seq = *(unsigned int*)(0x$wakeQueueAddress + (0 * $wakeEventStride) + $wakeEventSeqOffset)
    set `$_post_first_tick = *(unsigned long long*)(0x$wakeQueueAddress + (0 * $wakeEventStride) + $wakeEventTickOffset)
    set `$_post_first_cutoff_seq = *(unsigned int*)(0x$wakeQueueAddress + (30 * $wakeEventStride) + $wakeEventSeqOffset)
    set `$_post_first_cutoff_tick = *(unsigned long long*)(0x$wakeQueueAddress + (30 * $wakeEventStride) + $wakeEventTickOffset)
    set `$_post_first_last_seq = *(unsigned int*)(0x$wakeQueueAddress + (31 * $wakeEventStride) + $wakeEventSeqOffset)
    set `$_post_first_last_tick = *(unsigned long long*)(0x$wakeQueueAddress + (31 * $wakeEventStride) + $wakeEventTickOffset)
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $wakeQueuePopBeforeTickOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = (`$_expected_seq + 1)
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = `$_post_first_cutoff_tick
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = 99
    set `$_expected_seq = (`$_expected_seq + 1)
    set `$_stage = 9
  end
  continue
end
if `$_stage == 9
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == `$_expected_seq && *(unsigned int*)0x$wakeQueueCountAddress == 1 && *(unsigned int*)0x$wakeQueueHeadAddress == 1 && *(unsigned int*)0x$wakeQueueTailAddress == 0
    set `$_post_second_count = *(unsigned int*)0x$wakeQueueCountAddress
    set `$_post_second_head = *(unsigned int*)0x$wakeQueueHeadAddress
    set `$_post_second_tail = *(unsigned int*)0x$wakeQueueTailAddress
    set `$_post_second_overflow = *(unsigned int*)0x$wakeQueueOverflowAddress
    set `$_post_second_seq = *(unsigned int*)(0x$wakeQueueAddress + (0 * $wakeEventStride) + $wakeEventSeqOffset)
    set `$_post_second_tick = *(unsigned long long*)(0x$wakeQueueAddress + (0 * $wakeEventStride) + $wakeEventTickOffset)
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $wakeQueuePopBeforeTickOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = (`$_expected_seq + 1)
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = `$_post_second_tick
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = 1
    set `$_expected_seq = (`$_expected_seq + 1)
    set `$_stage = 10
  end
  continue
end
if `$_stage == 10
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == `$_expected_seq && *(unsigned int*)0x$wakeQueueCountAddress == 0 && *(unsigned int*)0x$wakeQueueHeadAddress == 0 && *(unsigned int*)0x$wakeQueueTailAddress == 0
    set `$_final_count = *(unsigned int*)0x$wakeQueueCountAddress
    set `$_final_head = *(unsigned int*)0x$wakeQueueHeadAddress
    set `$_final_tail = *(unsigned int*)0x$wakeQueueTailAddress
    set `$_final_overflow = *(unsigned int*)0x$wakeQueueOverflowAddress
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $wakeQueuePopBeforeTickOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = (`$_expected_seq + 1)
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = `$_post_second_tick
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = 1
    set `$_expected_seq = (`$_expected_seq + 1)
    set `$_stage = 11
  end
  continue
end
if `$_stage == 11
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == `$_expected_seq && *(short*)(0x$statusAddress+$statusLastCommandResultOffset) == $resultNotFound
    printf "AFTER_WAKE_QUEUE_BEFORE_TICK_OVERFLOW\n"
    printf "ACK=%u\n", *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset)
    printf "LAST_OPCODE=%u\n", *(unsigned short*)(0x$statusAddress+$statusLastCommandOpcodeOffset)
    printf "LAST_RESULT=%d\n", *(short*)(0x$statusAddress+$statusLastCommandResultOffset)
    printf "TICKS=%llu\n", *(unsigned long long*)(0x$statusAddress+$statusTicksOffset)
    printf "TASK_ID=%u\n", `$_task_id
    printf "WAKE_CYCLES=%u\n", `$_wake_cycles
    printf "PRE_COUNT=%u\n", `$_pre_count
    printf "PRE_HEAD=%u\n", `$_pre_head
    printf "PRE_TAIL=%u\n", `$_pre_tail
    printf "PRE_OVERFLOW=%u\n", `$_pre_overflow
    printf "PRE_FIRST_SEQ=%u\n", `$_pre_first_seq
    printf "PRE_FIRST_TICK=%llu\n", `$_pre_first_tick
    printf "PRE_CUTOFF_SEQ=%u\n", `$_pre_cutoff_seq
    printf "PRE_CUTOFF_TICK=%llu\n", `$_pre_cutoff_tick
    printf "PRE_LAST_SEQ=%u\n", `$_pre_last_seq
    printf "PRE_LAST_TICK=%llu\n", `$_pre_last_tick
    printf "POST_FIRST_COUNT=%u\n", `$_post_first_count
    printf "POST_FIRST_HEAD=%u\n", `$_post_first_head
    printf "POST_FIRST_TAIL=%u\n", `$_post_first_tail
    printf "POST_FIRST_OVERFLOW=%u\n", `$_post_first_overflow
    printf "POST_FIRST_SEQ=%u\n", `$_post_first_seq
    printf "POST_FIRST_TICK=%llu\n", `$_post_first_tick
    printf "POST_FIRST_CUTOFF_SEQ=%u\n", `$_post_first_cutoff_seq
    printf "POST_FIRST_CUTOFF_TICK=%llu\n", `$_post_first_cutoff_tick
    printf "POST_FIRST_LAST_SEQ=%u\n", `$_post_first_last_seq
    printf "POST_FIRST_LAST_TICK=%llu\n", `$_post_first_last_tick
    printf "POST_SECOND_COUNT=%u\n", `$_post_second_count
    printf "POST_SECOND_HEAD=%u\n", `$_post_second_head
    printf "POST_SECOND_TAIL=%u\n", `$_post_second_tail
    printf "POST_SECOND_OVERFLOW=%u\n", `$_post_second_overflow
    printf "POST_SECOND_SEQ=%u\n", `$_post_second_seq
    printf "POST_SECOND_TICK=%llu\n", `$_post_second_tick
    printf "FINAL_COUNT=%u\n", `$_final_count
    printf "FINAL_HEAD=%u\n", `$_final_head
    printf "FINAL_TAIL=%u\n", `$_final_tail
    printf "FINAL_OVERFLOW=%u\n", `$_final_overflow
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
    $hitAfter = $gdbOutput.Contains("AFTER_WAKE_QUEUE_BEFORE_TICK_OVERFLOW")
}
if (Test-Path $gdbStderr) {
    $gdbError = [string](Get-Content -Path $gdbStderr -Raw)
    if ($null -eq $gdbError) { $gdbError = "" }
}

if ($timedOut) { throw "QEMU Wake-queue before-tick overflow probe timed out after $TimeoutSeconds seconds.`nSTDOUT:`n$gdbOutput`nSTDERR:`n$gdbError" }
$gdbExitCode = if ($null -eq $gdbProc -or $null -eq $gdbProc.ExitCode) { 0 } else { [int] $gdbProc.ExitCode }
if ($gdbExitCode -ne 0) { throw "gdb exited with code $gdbExitCode.`nSTDOUT:`n$gdbOutput`nSTDERR:`n$gdbError" }
if (-not $hitStart -or -not $hitAfter) { throw "Wake-queue before-tick overflow probe did not reach expected checkpoints.`nSTDOUT:`n$gdbOutput`nSTDERR:`n$gdbError" }

$ack = Extract-IntValue -Text $gdbOutput -Name "ACK"
$lastOpcode = Extract-IntValue -Text $gdbOutput -Name "LAST_OPCODE"
$lastResult = Extract-IntValue -Text $gdbOutput -Name "LAST_RESULT"
$ticks = Extract-IntValue -Text $gdbOutput -Name "TICKS"
$taskId = Extract-IntValue -Text $gdbOutput -Name "TASK_ID"
$wakeCycles = Extract-IntValue -Text $gdbOutput -Name "WAKE_CYCLES"
$preCount = Extract-IntValue -Text $gdbOutput -Name "PRE_COUNT"
$preHead = Extract-IntValue -Text $gdbOutput -Name "PRE_HEAD"
$preTail = Extract-IntValue -Text $gdbOutput -Name "PRE_TAIL"
$preOverflow = Extract-IntValue -Text $gdbOutput -Name "PRE_OVERFLOW"
$preFirstSeq = Extract-IntValue -Text $gdbOutput -Name "PRE_FIRST_SEQ"
$preCutoffSeq = Extract-IntValue -Text $gdbOutput -Name "PRE_CUTOFF_SEQ"
$preLastSeq = Extract-IntValue -Text $gdbOutput -Name "PRE_LAST_SEQ"
$postFirstCount = Extract-IntValue -Text $gdbOutput -Name "POST_FIRST_COUNT"
$postFirstHead = Extract-IntValue -Text $gdbOutput -Name "POST_FIRST_HEAD"
$postFirstTail = Extract-IntValue -Text $gdbOutput -Name "POST_FIRST_TAIL"
$postFirstOverflow = Extract-IntValue -Text $gdbOutput -Name "POST_FIRST_OVERFLOW"
$postFirstSeq = Extract-IntValue -Text $gdbOutput -Name "POST_FIRST_SEQ"
$postFirstCutoffSeq = Extract-IntValue -Text $gdbOutput -Name "POST_FIRST_CUTOFF_SEQ"
$postFirstLastSeq = Extract-IntValue -Text $gdbOutput -Name "POST_FIRST_LAST_SEQ"
$postSecondCount = Extract-IntValue -Text $gdbOutput -Name "POST_SECOND_COUNT"
$postSecondHead = Extract-IntValue -Text $gdbOutput -Name "POST_SECOND_HEAD"
$postSecondTail = Extract-IntValue -Text $gdbOutput -Name "POST_SECOND_TAIL"
$postSecondOverflow = Extract-IntValue -Text $gdbOutput -Name "POST_SECOND_OVERFLOW"
$postSecondSeq = Extract-IntValue -Text $gdbOutput -Name "POST_SECOND_SEQ"
$finalCount = Extract-IntValue -Text $gdbOutput -Name "FINAL_COUNT"
$finalHead = Extract-IntValue -Text $gdbOutput -Name "FINAL_HEAD"
$finalTail = Extract-IntValue -Text $gdbOutput -Name "FINAL_TAIL"
$finalOverflow = Extract-IntValue -Text $gdbOutput -Name "FINAL_OVERFLOW"

if ($ack -ne $expectedFinalAck) { throw "Expected ACK=$expectedFinalAck, got $ack" }
if ($lastOpcode -ne $wakeQueuePopBeforeTickOpcode) { throw "Expected LAST_OPCODE=$wakeQueuePopBeforeTickOpcode, got $lastOpcode" }
if ($lastResult -ne $resultNotFound) { throw "Expected LAST_RESULT=$resultNotFound, got $lastResult" }
if ($ticks -lt $expectedFinalTickFloor) { throw "Expected TICKS >= $expectedFinalTickFloor, got $ticks" }
if ($taskId -ne 1) { throw "Expected TASK_ID=1, got $taskId" }
if ($wakeCycles -ne $overflowCycles) { throw "Expected WAKE_CYCLES=$overflowCycles, got $wakeCycles" }
if ($preCount -ne $wakeQueueCapacity -or $preHead -ne 2 -or $preTail -ne 2 -or $preOverflow -ne $expectedOverflow) { throw "Unexpected PRE queue summary: $preCount/$preHead/$preTail/$preOverflow" }
if ($preFirstSeq -ne 3 -or $preCutoffSeq -ne 34 -or $preLastSeq -ne 66) { throw "Unexpected PRE sequence summary: $preFirstSeq/$preCutoffSeq/$preLastSeq" }
if ($postFirstCount -ne 32 -or $postFirstHead -ne 32 -or $postFirstTail -ne 0 -or $postFirstOverflow -ne $expectedOverflow) { throw "Unexpected POST_FIRST queue summary: $postFirstCount/$postFirstHead/$postFirstTail/$postFirstOverflow" }
if ($postFirstSeq -ne 35 -or $postFirstCutoffSeq -ne 65 -or $postFirstLastSeq -ne 66) { throw "Unexpected POST_FIRST sequence summary: $postFirstSeq/$postFirstCutoffSeq/$postFirstLastSeq" }
if ($postSecondCount -ne 1 -or $postSecondHead -ne 1 -or $postSecondTail -ne 0 -or $postSecondOverflow -ne $expectedOverflow) { throw "Unexpected POST_SECOND queue summary: $postSecondCount/$postSecondHead/$postSecondTail/$postSecondOverflow" }
if ($postSecondSeq -ne 66) { throw "Unexpected POST_SECOND sequence summary: $postSecondSeq" }
if ($finalCount -ne 0 -or $finalHead -ne 0 -or $finalTail -ne 0 -or $finalOverflow -ne $expectedOverflow) { throw "Unexpected FINAL queue summary: $finalCount/$finalHead/$finalTail/$finalOverflow" }

Write-Output "BAREMETAL_QEMU_AVAILABLE=True"
Write-Output "BAREMETAL_QEMU_BINARY=$qemu"
Write-Output "BAREMETAL_GDB_BINARY=$gdb"
Write-Output "BAREMETAL_NM_BINARY=$nm"
Write-Output "BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_OVERFLOW_PROBE=pass"
Write-Output "ACK=$ack"
Write-Output "LAST_OPCODE=$lastOpcode"
Write-Output "LAST_RESULT=$lastResult"
Write-Output "TICKS=$ticks"
Write-Output "TASK_ID=$taskId"
Write-Output "WAKE_CYCLES=$wakeCycles"
Write-Output "PRE_COUNT=$preCount"
Write-Output "PRE_HEAD=$preHead"
Write-Output "PRE_TAIL=$preTail"
Write-Output "PRE_OVERFLOW=$preOverflow"
Write-Output "PRE_FIRST_SEQ=$preFirstSeq"
Write-Output "PRE_CUTOFF_SEQ=$preCutoffSeq"
Write-Output "PRE_LAST_SEQ=$preLastSeq"
Write-Output "POST_FIRST_COUNT=$postFirstCount"
Write-Output "POST_FIRST_HEAD=$postFirstHead"
Write-Output "POST_FIRST_TAIL=$postFirstTail"
Write-Output "POST_FIRST_OVERFLOW=$postFirstOverflow"
Write-Output "POST_FIRST_SEQ=$postFirstSeq"
Write-Output "POST_FIRST_CUTOFF_SEQ=$postFirstCutoffSeq"
Write-Output "POST_FIRST_LAST_SEQ=$postFirstLastSeq"
Write-Output "POST_SECOND_COUNT=$postSecondCount"
Write-Output "POST_SECOND_HEAD=$postSecondHead"
Write-Output "POST_SECOND_TAIL=$postSecondTail"
Write-Output "POST_SECOND_OVERFLOW=$postSecondOverflow"
Write-Output "POST_SECOND_SEQ=$postSecondSeq"
Write-Output "FINAL_COUNT=$finalCount"
Write-Output "FINAL_HEAD=$finalHead"
Write-Output "FINAL_TAIL=$finalTail"
Write-Output "FINAL_OVERFLOW=$finalOverflow"
