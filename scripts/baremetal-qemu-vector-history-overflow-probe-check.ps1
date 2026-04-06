# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 30,
    [int] $GdbPort = 1251
)

$ErrorActionPreference = "Stop"

$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$releaseDir = Join-Path $repo "release"
$prerequisiteScript = Join-Path $PSScriptRoot "baremetal-qemu-descriptor-bootdiag-probe-check.ps1"
$artifact = Join-Path $releaseDir "openclaw-zig-baremetal-pvh-descriptor-bootdiag-probe.elf"
$gdbScript = Join-Path $releaseDir "qemu-vector-history-overflow-probe.gdb"
$gdbStdout = Join-Path $releaseDir "qemu-vector-history-overflow-probe.gdb.stdout.log"
$gdbStderr = Join-Path $releaseDir "qemu-vector-history-overflow-probe.gdb.stderr.log"
$qemuStdout = Join-Path $releaseDir "qemu-vector-history-overflow-probe.qemu.stdout.log"
$qemuStderr = Join-Path $releaseDir "qemu-vector-history-overflow-probe.qemu.stderr.log"

$triggerInterruptOpcode = 7
$resetInterruptCountersOpcode = 8
$triggerExceptionOpcode = 12
$resetExceptionCountersOpcode = 11
$clearExceptionHistoryOpcode = 13
$clearInterruptHistoryOpcode = 14
$resetVectorCountersOpcode = 15

$interruptVector = 200
$interruptCountTarget = 35
$exceptionVector = 13
$exceptionCountTarget = 19
$exceptionCodeBase = 100
$interruptHistoryCapacity = 32
$exceptionHistoryCapacity = 16
$interruptHistoryExpectedOverflow = $interruptCountTarget - $interruptHistoryCapacity
$exceptionHistoryExpectedOverflow = $exceptionCountTarget - $exceptionHistoryCapacity
$expectedExceptionNewestCode = $exceptionCodeBase + $exceptionCountTarget - 1

$statusTicksOffset = 8
$statusCommandSeqAckOffset = 28
$statusLastCommandOpcodeOffset = 32
$statusLastCommandResultOffset = 34

$commandOpcodeOffset = 6
$commandSeqOffset = 8
$commandArg0Offset = 16
$commandArg1Offset = 24

$interruptStateLastInterruptVectorOffset = 2
$interruptStateInterruptCountOffset = 16
$interruptStateLastExceptionVectorOffset = 24
$interruptStateExceptionCountOffset = 32
$interruptStateLastExceptionCodeOffset = 40
$interruptStateExceptionHistoryLenOffset = 48
$interruptStateExceptionHistoryOverflowOffset = 52
$interruptStateInterruptHistoryLenOffset = 56
$interruptStateInterruptHistoryOverflowOffset = 60

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

function Invoke-DescriptorArtifactBuildIfNeeded {
    if ($SkipBuild -and -not (Test-Path $artifact)) { throw "Vector/history overflow prerequisite artifact not found at $artifact and -SkipBuild was supplied." }
    if ($SkipBuild) { return }
    if (-not (Test-Path $prerequisiteScript)) { throw "Prerequisite script not found: $prerequisiteScript" }
    $prereqOutput = & $prerequisiteScript 2>&1
    $prereqExitCode = $LASTEXITCODE
    if ($prereqExitCode -ne 0) {
        if ($null -ne $prereqOutput) { $prereqOutput | Write-Output }
        throw "Descriptor bootdiag prerequisite failed with exit code $prereqExitCode"
    }
}

Set-Location $repo
New-Item -ItemType Directory -Force -Path $releaseDir | Out-Null

$qemu = Resolve-QemuExecutable
$gdb = Resolve-GdbExecutable
$nm = Resolve-NmExecutable

if ($null -eq $qemu) {
    Write-Output "BAREMETAL_QEMU_AVAILABLE=False"
    Write-Output "BAREMETAL_QEMU_VECTOR_HISTORY_OVERFLOW_PROBE=skipped"
    exit 0
}
if ($null -eq $gdb) {
    Write-Output "BAREMETAL_QEMU_AVAILABLE=True"
    Write-Output "BAREMETAL_QEMU_BINARY=$qemu"
    Write-Output "BAREMETAL_GDB_AVAILABLE=False"
    Write-Output "BAREMETAL_QEMU_VECTOR_HISTORY_OVERFLOW_PROBE=skipped"
    exit 0
}
if ($null -eq $nm) {
    Write-Output "BAREMETAL_QEMU_AVAILABLE=True"
    Write-Output "BAREMETAL_QEMU_BINARY=$qemu"
    Write-Output "BAREMETAL_GDB_BINARY=$gdb"
    Write-Output "BAREMETAL_NM_AVAILABLE=False"
    Write-Output "BAREMETAL_QEMU_VECTOR_HISTORY_OVERFLOW_PROBE=skipped"
    exit 0
}

if (-not (Test-Path $artifact)) {
    Invoke-DescriptorArtifactBuildIfNeeded
} elseif (-not $SkipBuild) {
    Invoke-DescriptorArtifactBuildIfNeeded
}

if (-not (Test-Path $artifact)) {
    Write-Output "BAREMETAL_QEMU_AVAILABLE=True"
    Write-Output "BAREMETAL_QEMU_BINARY=$qemu"
    Write-Output "BAREMETAL_GDB_BINARY=$gdb"
    Write-Output "BAREMETAL_NM_BINARY=$nm"
    Write-Output "BAREMETAL_QEMU_VECTOR_HISTORY_OVERFLOW_PROBE=skipped"
    exit 0
}

$symbolOutput = & $nm $artifact
if ($LASTEXITCODE -ne 0 -or $null -eq $symbolOutput -or $symbolOutput.Count -eq 0) {
    throw "Failed to resolve symbol table from $artifact using $nm"
}

$startAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[Tt]\s_start$' -SymbolName "_start"
$spinPauseAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[tT]\sbaremetal_main\.spinPause$' -SymbolName "baremetal_main.spinPause"
$statusAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[dDbB]\sbaremetal_main\.status$' -SymbolName "baremetal_main.status"
$commandMailboxAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[dDbB]\sbaremetal_main\.command_mailbox$' -SymbolName "baremetal_main.command_mailbox"
$interruptStateAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[dDbB]\sbaremetal\.x86_bootstrap\.interrupt_state$' -SymbolName "baremetal.x86_bootstrap.interrupt_state"
$interruptVectorCountsAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[dDbB]\sbaremetal\.x86_bootstrap\.interrupt_vector_counts$' -SymbolName "baremetal.x86_bootstrap.interrupt_vector_counts"
$exceptionVectorCountsAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[dDbB]\sbaremetal\.x86_bootstrap\.exception_vector_counts$' -SymbolName "baremetal.x86_bootstrap.exception_vector_counts"

$artifactForGdb = $artifact.Replace('\', '/')
if (Test-Path $gdbStdout) { Remove-Item -Force $gdbStdout }
if (Test-Path $gdbStderr) { Remove-Item -Force $gdbStderr }
if (Test-Path $qemuStdout) { Remove-Item -Force $qemuStdout }
if (Test-Path $qemuStderr) { Remove-Item -Force $qemuStderr }

@"
set pagination off
set confirm off
set `$stage = 0
set `$expected_seq = 0
set `$interrupt_emitted = 0
set `$exception_emitted = 0
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
if `$stage == 0
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == 0
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $resetInterruptCountersOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = 1
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = 0
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = 0
    set `$expected_seq = 1
    set `$stage = 1
  end
  continue
end
if `$stage == 1
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == `$expected_seq && *(unsigned long long*)(0x$interruptStateAddress+$interruptStateInterruptCountOffset) == 0
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $clearInterruptHistoryOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = `$expected_seq + 1
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = 0
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = 0
    set `$expected_seq = `$expected_seq + 1
    set `$stage = 2
  end
  continue
end
if `$stage == 2
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == `$expected_seq && *(unsigned int*)(0x$interruptStateAddress+$interruptStateInterruptHistoryLenOffset) == 0
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $resetVectorCountersOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = `$expected_seq + 1
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = 0
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = 0
    set `$expected_seq = `$expected_seq + 1
    set `$stage = 3
  end
  continue
end
if `$stage == 3
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == `$expected_seq && *((unsigned long long*)0x$interruptVectorCountsAddress + $interruptVector) == 0
    set `$interrupt_emitted = 0
    set `$stage = 4
  end
  continue
end
if `$stage == 4
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == `$expected_seq && `$interrupt_emitted < $interruptCountTarget
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $triggerInterruptOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = `$expected_seq + 1
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = $interruptVector
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = 0
    set `$expected_seq = `$expected_seq + 1
    set `$interrupt_emitted = `$interrupt_emitted + 1
    if `$interrupt_emitted == $interruptCountTarget
      set `$stage = 5
    end
  end
  continue
end
if `$stage == 5
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == `$expected_seq && *(unsigned long long*)(0x$interruptStateAddress+$interruptStateInterruptCountOffset) == $interruptCountTarget && *(unsigned int*)(0x$interruptStateAddress+$interruptStateInterruptHistoryLenOffset) == $interruptHistoryCapacity && *(unsigned int*)(0x$interruptStateAddress+$interruptStateInterruptHistoryOverflowOffset) == $interruptHistoryExpectedOverflow && *((unsigned long long*)0x$interruptVectorCountsAddress + $interruptVector) == $interruptCountTarget
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $resetExceptionCountersOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = `$expected_seq + 1
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = 0
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = 0
    set `$expected_seq = `$expected_seq + 1
    set `$stage = 6
  end
  continue
end
if `$stage == 6
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == `$expected_seq && *(unsigned long long*)(0x$interruptStateAddress+$interruptStateExceptionCountOffset) == 0
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $clearExceptionHistoryOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = `$expected_seq + 1
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = 0
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = 0
    set `$expected_seq = `$expected_seq + 1
    set `$stage = 7
  end
  continue
end
if `$stage == 7
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == `$expected_seq && *(unsigned int*)(0x$interruptStateAddress+$interruptStateExceptionHistoryLenOffset) == 0
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $resetInterruptCountersOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = `$expected_seq + 1
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = 0
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = 0
    set `$expected_seq = `$expected_seq + 1
    set `$stage = 8
  end
  continue
end
if `$stage == 8
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == `$expected_seq && *(unsigned long long*)(0x$interruptStateAddress+$interruptStateInterruptCountOffset) == 0
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $clearInterruptHistoryOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = `$expected_seq + 1
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = 0
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = 0
    set `$expected_seq = `$expected_seq + 1
    set `$stage = 9
  end
  continue
end
if `$stage == 9
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == `$expected_seq && *(unsigned int*)(0x$interruptStateAddress+$interruptStateInterruptHistoryLenOffset) == 0
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $resetVectorCountersOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = `$expected_seq + 1
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = 0
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = 0
    set `$expected_seq = `$expected_seq + 1
    set `$stage = 10
  end
  continue
end
if `$stage == 10
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == `$expected_seq && *((unsigned long long*)0x$interruptVectorCountsAddress + $exceptionVector) == 0 && *((unsigned long long*)0x$exceptionVectorCountsAddress + $exceptionVector) == 0
    set `$exception_emitted = 0
    set `$stage = 11
  end
  continue
end
if `$stage == 11
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == `$expected_seq && `$exception_emitted < $exceptionCountTarget
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $triggerExceptionOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = `$expected_seq + 1
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = $exceptionVector
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = $exceptionCodeBase + `$exception_emitted
    set `$expected_seq = `$expected_seq + 1
    set `$exception_emitted = `$exception_emitted + 1
    if `$exception_emitted == $exceptionCountTarget
      set `$stage = 12
    end
  end
  continue
end
if `$stage == 12
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == `$expected_seq && *(unsigned long long*)(0x$interruptStateAddress+$interruptStateExceptionCountOffset) == $exceptionCountTarget && *(unsigned int*)(0x$interruptStateAddress+$interruptStateExceptionHistoryLenOffset) == $exceptionHistoryCapacity && *(unsigned int*)(0x$interruptStateAddress+$interruptStateExceptionHistoryOverflowOffset) == $exceptionHistoryExpectedOverflow && *((unsigned long long*)0x$interruptVectorCountsAddress + $exceptionVector) == $exceptionCountTarget && *((unsigned long long*)0x$exceptionVectorCountsAddress + $exceptionVector) == $exceptionCountTarget
    printf "HIT_AFTER_VECTOR_HISTORY_OVERFLOW_PROBE\n"
    printf "ACK=%u\n", *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset)
    printf "LAST_OPCODE=%u\n", *(unsigned short*)(0x$statusAddress+$statusLastCommandOpcodeOffset)
    printf "LAST_RESULT=%d\n", *(short*)(0x$statusAddress+$statusLastCommandResultOffset)
    printf "TICKS=%llu\n", *(unsigned long long*)(0x$statusAddress+$statusTicksOffset)
    printf "INTERRUPT_COUNT_PHASE_A=%llu\n", $interruptCountTarget
    printf "INTERRUPT_VECTOR_200_COUNT_PHASE_A=%u\n", $interruptCountTarget
    printf "INTERRUPT_HISTORY_LEN_PHASE_A=%u\n", $interruptHistoryCapacity
    printf "INTERRUPT_HISTORY_OVERFLOW_PHASE_A=%u\n", $interruptHistoryExpectedOverflow
    printf "INTERRUPT_COUNT_PHASE_B=%llu\n", *(unsigned long long*)(0x$interruptStateAddress+$interruptStateInterruptCountOffset)
    printf "EXCEPTION_COUNT_PHASE_B=%llu\n", *(unsigned long long*)(0x$interruptStateAddress+$interruptStateExceptionCountOffset)
    printf "INTERRUPT_VECTOR_13_COUNT_PHASE_B=%llu\n", *((unsigned long long*)0x$interruptVectorCountsAddress + $exceptionVector)
    printf "EXCEPTION_VECTOR_13_COUNT_PHASE_B=%llu\n", *((unsigned long long*)0x$exceptionVectorCountsAddress + $exceptionVector)
    printf "EXCEPTION_HISTORY_LEN_PHASE_B=%u\n", *(unsigned int*)(0x$interruptStateAddress+$interruptStateExceptionHistoryLenOffset)
    printf "EXCEPTION_HISTORY_OVERFLOW_PHASE_B=%u\n", *(unsigned int*)(0x$interruptStateAddress+$interruptStateExceptionHistoryOverflowOffset)
    printf "INTERRUPT_HISTORY_LEN_PHASE_B=%u\n", *(unsigned int*)(0x$interruptStateAddress+$interruptStateInterruptHistoryLenOffset)
    printf "INTERRUPT_HISTORY_OVERFLOW_PHASE_B=%u\n", *(unsigned int*)(0x$interruptStateAddress+$interruptStateInterruptHistoryOverflowOffset)
    printf "LAST_INTERRUPT_VECTOR_PHASE_B=%u\n", *(unsigned char*)(0x$interruptStateAddress+$interruptStateLastInterruptVectorOffset)
    printf "LAST_EXCEPTION_VECTOR_PHASE_B=%u\n", *(unsigned char*)(0x$interruptStateAddress+$interruptStateLastExceptionVectorOffset)
    printf "LAST_EXCEPTION_CODE_PHASE_B=%llu\n", *(unsigned long long*)(0x$interruptStateAddress+$interruptStateLastExceptionCodeOffset)
    detach
    quit
  end
  continue
end
continue
end
continue
"@ | Set-Content -Path $gdbScript -NoNewline

$qemuArgs = @(
    "-kernel", $artifact,
    "-display", "none",
    "-no-reboot",
    "-no-shutdown",
    "-S",
    "-gdb", "tcp::$GdbPort"
)

$qemuProcess = $null
try {
    $qemuProcess = Start-Process -FilePath $qemu -ArgumentList $qemuArgs -PassThru -RedirectStandardOutput $qemuStdout -RedirectStandardError $qemuStderr
    Start-Sleep -Milliseconds 500

    $gdbProcess = Start-Process -FilePath $gdb -ArgumentList @("-q", "-x", $gdbScript) -PassThru -Wait -RedirectStandardOutput $gdbStdout -RedirectStandardError $gdbStderr
    $gdbExitCode = $gdbProcess.ExitCode
    $gdbText = if (Test-Path $gdbStdout) { Get-Content $gdbStdout -Raw } else { "" }
    if ($gdbExitCode -ne 0) {
        if ($gdbText) { $gdbText | Write-Output }
        throw "GDB probe failed with exit code $gdbExitCode"
    }
    $gdbText | Set-Content -Path $gdbStdout
    $gdbText | Write-Output

    if ($gdbText -notmatch 'HIT_START' -or $gdbText -notmatch 'HIT_AFTER_VECTOR_HISTORY_OVERFLOW_PROBE') {
        throw "Probe did not reach all expected stages."
    }

    $ack = Extract-IntValue -Text $gdbText -Name "ACK"
    $lastOpcode = Extract-IntValue -Text $gdbText -Name "LAST_OPCODE"
    $lastResult = Extract-IntValue -Text $gdbText -Name "LAST_RESULT"
    $ticks = Extract-IntValue -Text $gdbText -Name "TICKS"
    $interruptCountPhaseA = Extract-IntValue -Text $gdbText -Name "INTERRUPT_COUNT_PHASE_A"
    $interruptVectorCountPhaseA = Extract-IntValue -Text $gdbText -Name "INTERRUPT_VECTOR_200_COUNT_PHASE_A"
    $interruptHistoryLenPhaseA = Extract-IntValue -Text $gdbText -Name "INTERRUPT_HISTORY_LEN_PHASE_A"
    $interruptHistoryOverflowPhaseA = Extract-IntValue -Text $gdbText -Name "INTERRUPT_HISTORY_OVERFLOW_PHASE_A"
    $interruptCountPhaseB = Extract-IntValue -Text $gdbText -Name "INTERRUPT_COUNT_PHASE_B"
    $exceptionCountPhaseB = Extract-IntValue -Text $gdbText -Name "EXCEPTION_COUNT_PHASE_B"
    $interruptVectorCountPhaseB = Extract-IntValue -Text $gdbText -Name "INTERRUPT_VECTOR_13_COUNT_PHASE_B"
    $exceptionVectorCountPhaseB = Extract-IntValue -Text $gdbText -Name "EXCEPTION_VECTOR_13_COUNT_PHASE_B"
    $exceptionHistoryLenPhaseB = Extract-IntValue -Text $gdbText -Name "EXCEPTION_HISTORY_LEN_PHASE_B"
    $exceptionHistoryOverflowPhaseB = Extract-IntValue -Text $gdbText -Name "EXCEPTION_HISTORY_OVERFLOW_PHASE_B"
    $interruptHistoryLenPhaseB = Extract-IntValue -Text $gdbText -Name "INTERRUPT_HISTORY_LEN_PHASE_B"
    $interruptHistoryOverflowPhaseB = Extract-IntValue -Text $gdbText -Name "INTERRUPT_HISTORY_OVERFLOW_PHASE_B"
    $lastInterruptVectorPhaseB = Extract-IntValue -Text $gdbText -Name "LAST_INTERRUPT_VECTOR_PHASE_B"
    $lastExceptionVectorPhaseB = Extract-IntValue -Text $gdbText -Name "LAST_EXCEPTION_VECTOR_PHASE_B"
    $lastExceptionCodePhaseB = Extract-IntValue -Text $gdbText -Name "LAST_EXCEPTION_CODE_PHASE_B"

    if ($null -in @($ack, $lastOpcode, $lastResult, $ticks, $interruptCountPhaseA, $interruptVectorCountPhaseA,
            $interruptHistoryLenPhaseA, $interruptHistoryOverflowPhaseA, $interruptCountPhaseB, $exceptionCountPhaseB,
            $interruptVectorCountPhaseB, $exceptionVectorCountPhaseB, $exceptionHistoryLenPhaseB, $exceptionHistoryOverflowPhaseB,
            $interruptHistoryLenPhaseB, $interruptHistoryOverflowPhaseB, $lastInterruptVectorPhaseB, $lastExceptionVectorPhaseB,
            $lastExceptionCodePhaseB)) {
        throw "Probe output was missing one or more expected values."
    }

    if ($ack -ne 62) { throw "Expected final ACK 62, got $ack" }
    if ($lastOpcode -ne $triggerExceptionOpcode) { throw "Expected final opcode $triggerExceptionOpcode, got $lastOpcode" }
    if ($lastResult -ne 0) { throw "Expected final result 0, got $lastResult" }
    if ($ticks -lt 62) { throw "Expected ticks >= 62, got $ticks" }
    if ($interruptCountPhaseA -ne $interruptCountTarget) { throw "Expected phase A interrupt count $interruptCountTarget, got $interruptCountPhaseA" }
    if ($interruptVectorCountPhaseA -ne $interruptCountTarget) { throw "Expected phase A vector count $interruptCountTarget, got $interruptVectorCountPhaseA" }
    if ($interruptHistoryLenPhaseA -ne $interruptHistoryCapacity) { throw "Expected phase A history len $interruptHistoryCapacity, got $interruptHistoryLenPhaseA" }
    if ($interruptHistoryOverflowPhaseA -ne $interruptHistoryExpectedOverflow) { throw "Expected phase A history overflow $interruptHistoryExpectedOverflow, got $interruptHistoryOverflowPhaseA" }
    if ($interruptCountPhaseB -ne $exceptionCountTarget) { throw "Expected phase B interrupt count $exceptionCountTarget, got $interruptCountPhaseB" }
    if ($exceptionCountPhaseB -ne $exceptionCountTarget) { throw "Expected phase B exception count $exceptionCountTarget, got $exceptionCountPhaseB" }
    if ($interruptVectorCountPhaseB -ne $exceptionCountTarget) { throw "Expected phase B interrupt vector count $exceptionCountTarget, got $interruptVectorCountPhaseB" }
    if ($exceptionVectorCountPhaseB -ne $exceptionCountTarget) { throw "Expected phase B exception vector count $exceptionCountTarget, got $exceptionVectorCountPhaseB" }
    if ($exceptionHistoryLenPhaseB -ne $exceptionHistoryCapacity) { throw "Expected phase B exception history len $exceptionHistoryCapacity, got $exceptionHistoryLenPhaseB" }
    if ($exceptionHistoryOverflowPhaseB -ne $exceptionHistoryExpectedOverflow) { throw "Expected phase B exception history overflow $exceptionHistoryExpectedOverflow, got $exceptionHistoryOverflowPhaseB" }
    if ($interruptHistoryLenPhaseB -ne $exceptionCountTarget) { throw "Expected phase B interrupt history len $exceptionCountTarget, got $interruptHistoryLenPhaseB" }
    if ($interruptHistoryOverflowPhaseB -ne 0) { throw "Expected phase B interrupt history overflow 0, got $interruptHistoryOverflowPhaseB" }
    if ($lastInterruptVectorPhaseB -ne $exceptionVector) { throw "Expected phase B last interrupt vector $exceptionVector, got $lastInterruptVectorPhaseB" }
    if ($lastExceptionVectorPhaseB -ne $exceptionVector) { throw "Expected phase B last exception vector $exceptionVector, got $lastExceptionVectorPhaseB" }
    if ($lastExceptionCodePhaseB -ne $expectedExceptionNewestCode) { throw "Expected phase B last exception code $expectedExceptionNewestCode, got $lastExceptionCodePhaseB" }

    Write-Output "BAREMETAL_QEMU_AVAILABLE=True"
    Write-Output "BAREMETAL_QEMU_BINARY=$qemu"
    Write-Output "BAREMETAL_GDB_BINARY=$gdb"
    Write-Output "BAREMETAL_NM_BINARY=$nm"
    Write-Output "BAREMETAL_QEMU_VECTOR_HISTORY_OVERFLOW_PROBE=pass"
} finally {
    if ($null -ne $qemuProcess -and -not $qemuProcess.HasExited) {
        Stop-Process -Id $qemuProcess.Id -Force
        $qemuProcess.WaitForExit()
    }
}







