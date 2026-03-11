param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 30,
    [int] $GdbPort = 1250
)

$ErrorActionPreference = "Stop"

$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$releaseDir = Join-Path $repo "release"
$prerequisiteScript = Join-Path $PSScriptRoot "baremetal-qemu-descriptor-bootdiag-probe-check.ps1"
$artifact = Join-Path $releaseDir "openclaw-zig-baremetal-pvh-descriptor-bootdiag-probe.elf"
$gdbScript = Join-Path $releaseDir "qemu-descriptor-dispatch-probe.gdb"
$gdbStdout = Join-Path $releaseDir "qemu-descriptor-dispatch-probe.gdb.stdout.log"
$gdbStderr = Join-Path $releaseDir "qemu-descriptor-dispatch-probe.gdb.stderr.log"
$qemuStdout = Join-Path $releaseDir "qemu-descriptor-dispatch-probe.qemu.stdout.log"
$qemuStderr = Join-Path $releaseDir "qemu-descriptor-dispatch-probe.qemu.stderr.log"

$triggerInterruptOpcode = 7
$resetInterruptCountersOpcode = 8
$loadDescriptorTablesOpcode = 10
$resetExceptionCountersOpcode = 11
$triggerExceptionOpcode = 12
$clearExceptionHistoryOpcode = 13
$clearInterruptHistoryOpcode = 14
$reinitDescriptorTablesOpcode = 9

$interruptVector = 44
$exceptionVector = 13
$exceptionCode = 51966

$statusTicksOffset = 8
$statusCommandSeqAckOffset = 28
$statusLastCommandOpcodeOffset = 32
$statusLastCommandResultOffset = 34

$commandOpcodeOffset = 6
$commandSeqOffset = 8
$commandArg0Offset = 16
$commandArg1Offset = 24

$interruptDescriptorReadyOffset = 0
$interruptDescriptorLoadedOffset = 1
$interruptStateLastInterruptVectorOffset = 2
$interruptLoadAttemptsOffset = 4
$interruptLoadSuccessesOffset = 8
$interruptDescriptorInitCountOffset = 12
$interruptStateInterruptCountOffset = 16
$interruptStateLastExceptionVectorOffset = 24
$interruptStateExceptionCountOffset = 32
$interruptStateLastExceptionCodeOffset = 40
$interruptStateExceptionHistoryLenOffset = 48
$interruptStateInterruptHistoryLenOffset = 56

$interruptEventStride = 32
$interruptEventSeqOffset = 0
$interruptEventVectorOffset = 4
$interruptEventIsExceptionOffset = 5
$interruptEventCodeOffset = 8
$interruptEventInterruptCountOffset = 16
$interruptEventExceptionCountOffset = 24

$exceptionEventStride = 32
$exceptionEventSeqOffset = 0
$exceptionEventVectorOffset = 4
$exceptionEventCodeOffset = 8
$exceptionEventInterruptCountOffset = 16
$exceptionEventExceptionCountOffset = 24

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
    param([switch] $Force)
    if ($SkipBuild -and $Force) { throw "Descriptor dispatch probe artifact is stale or missing and -SkipBuild was supplied." }
    if ($SkipBuild -and -not (Test-Path $artifact)) { throw "Descriptor dispatch prerequisite artifact not found at $artifact and -SkipBuild was supplied." }
    if ($SkipBuild -and -not $Force) { return }
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
    Write-Output "BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE=skipped"
    exit 0
}
if ($null -eq $gdb) {
    Write-Output "BAREMETAL_QEMU_AVAILABLE=True"
    Write-Output "BAREMETAL_QEMU_BINARY=$qemu"
    Write-Output "BAREMETAL_GDB_AVAILABLE=False"
    Write-Output "BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE=skipped"
    exit 0
}
if ($null -eq $nm) {
    Write-Output "BAREMETAL_QEMU_AVAILABLE=True"
    Write-Output "BAREMETAL_QEMU_BINARY=$qemu"
    Write-Output "BAREMETAL_GDB_BINARY=$gdb"
    Write-Output "BAREMETAL_NM_AVAILABLE=False"
    Write-Output "BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE=skipped"
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
    Write-Output "BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE=skipped"
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
$interruptHistoryAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[dDbB]\sbaremetal\.x86_bootstrap\.interrupt_history$' -SymbolName "baremetal.x86_bootstrap.interrupt_history"
$exceptionHistoryAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[dDbB]\sbaremetal\.x86_bootstrap\.exception_history$' -SymbolName "baremetal.x86_bootstrap.exception_history"
$artifactForGdb = $artifact.Replace('\', '/')
if (Test-Path $gdbStdout) { Remove-Item -Force $gdbStdout }
if (Test-Path $gdbStderr) { Remove-Item -Force $gdbStderr }
if (Test-Path $qemuStdout) { Remove-Item -Force $qemuStdout }
if (Test-Path $qemuStderr) { Remove-Item -Force $qemuStderr }

@"
set pagination off
set confirm off
set `$stage = 0
set `$descriptor_init_before = 0
set `$load_attempts_before = 0
set `$load_successes_before = 0
set `$interrupt_seq = 0
set `$interrupt_vector = 0
set `$interrupt_is_exception = 0
set `$interrupt_code = 0
set `$interrupt_interrupt_count = 0
set `$interrupt_exception_count = 0
set `$interrupt2_seq = 0
set `$interrupt2_vector = 0
set `$interrupt2_is_exception = 0
set `$interrupt2_code = 0
set `$interrupt2_interrupt_count = 0
set `$interrupt2_exception_count = 0
set `$exception_seq = 0
set `$exception_vector = 0
set `$exception_code = 0
set `$exception_interrupt_count = 0
set `$exception_exception_count = 0
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
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == 0 && *(unsigned char*)(0x$interruptStateAddress+$interruptDescriptorReadyOffset) == 1 && *(unsigned char*)(0x$interruptStateAddress+$interruptDescriptorLoadedOffset) == 1
    set `$descriptor_init_before = *(unsigned int*)(0x$interruptStateAddress+$interruptDescriptorInitCountOffset)
    set `$load_attempts_before = *(unsigned int*)(0x$interruptStateAddress+$interruptLoadAttemptsOffset)
    set `$load_successes_before = *(unsigned int*)(0x$interruptStateAddress+$interruptLoadSuccessesOffset)
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $reinitDescriptorTablesOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = 1
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = 0
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = 0
    set `$stage = 1
  end
  continue
end
if `$stage == 1
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == 1 && *(unsigned int*)(0x$interruptStateAddress+$interruptDescriptorInitCountOffset) == (`$descriptor_init_before + 1)
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $loadDescriptorTablesOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = 2
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = 0
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = 0
    set `$stage = 2
  end
  continue
end
if `$stage == 2
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == 2 && *(unsigned int*)(0x$interruptStateAddress+$interruptLoadAttemptsOffset) == (`$load_attempts_before + 1) && *(unsigned int*)(0x$interruptStateAddress+$interruptLoadSuccessesOffset) == (`$load_successes_before + 1)
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $resetInterruptCountersOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = 3
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = 0
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = 0
    set `$stage = 3
  end
  continue
end
if `$stage == 3
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == 3 && *(unsigned long long*)(0x$interruptStateAddress+$interruptStateInterruptCountOffset) == 0
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $resetExceptionCountersOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = 4
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = 0
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = 0
    set `$stage = 4
  end
  continue
end
if `$stage == 4
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == 4 && *(unsigned long long*)(0x$interruptStateAddress+$interruptStateExceptionCountOffset) == 0
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $clearInterruptHistoryOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = 5
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = 0
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = 0
    set `$stage = 5
  end
  continue
end
if `$stage == 5
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == 5 && *(unsigned int*)(0x$interruptStateAddress+$interruptStateInterruptHistoryLenOffset) == 0
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $clearExceptionHistoryOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = 6
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = 0
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = 0
    set `$stage = 6
  end
  continue
end
if `$stage == 6
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == 6 && *(unsigned int*)(0x$interruptStateAddress+$interruptStateExceptionHistoryLenOffset) == 0
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $triggerInterruptOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = 7
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = $interruptVector
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = 0
    set `$stage = 7
  end
  continue
end
if `$stage == 7
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == 7 && *(unsigned char*)(0x$interruptStateAddress+$interruptStateLastInterruptVectorOffset) == $interruptVector && *(unsigned long long*)(0x$interruptStateAddress+$interruptStateInterruptCountOffset) == 1 && *(unsigned int*)(0x$interruptStateAddress+$interruptStateInterruptHistoryLenOffset) == 1
    set `$interrupt_seq = *(unsigned int*)(0x$interruptHistoryAddress+$interruptEventSeqOffset)
    set `$interrupt_vector = *(unsigned char*)(0x$interruptHistoryAddress+$interruptEventVectorOffset)
    set `$interrupt_is_exception = *(unsigned char*)(0x$interruptHistoryAddress+$interruptEventIsExceptionOffset)
    set `$interrupt_code = *(unsigned long long*)(0x$interruptHistoryAddress+$interruptEventCodeOffset)
    set `$interrupt_interrupt_count = *(unsigned long long*)(0x$interruptHistoryAddress+$interruptEventInterruptCountOffset)
    set `$interrupt_exception_count = *(unsigned long long*)(0x$interruptHistoryAddress+$interruptEventExceptionCountOffset)
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $triggerExceptionOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = 8
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = $exceptionVector
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = $exceptionCode
    set `$stage = 8
  end
  continue
end
if `$stage == 8
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == 8 && *(unsigned char*)(0x$interruptStateAddress+$interruptStateLastInterruptVectorOffset) == $exceptionVector && *(unsigned char*)(0x$interruptStateAddress+$interruptStateLastExceptionVectorOffset) == $exceptionVector && *(unsigned long long*)(0x$interruptStateAddress+$interruptStateInterruptCountOffset) == 2 && *(unsigned long long*)(0x$interruptStateAddress+$interruptStateExceptionCountOffset) == 1 && *(unsigned long long*)(0x$interruptStateAddress+$interruptStateLastExceptionCodeOffset) == $exceptionCode && *(unsigned int*)(0x$interruptStateAddress+$interruptStateInterruptHistoryLenOffset) == 2 && *(unsigned int*)(0x$interruptStateAddress+$interruptStateExceptionHistoryLenOffset) == 1
    set `$interrupt2_seq = *(unsigned int*)(0x$interruptHistoryAddress+$interruptEventStride+$interruptEventSeqOffset)
    set `$interrupt2_vector = *(unsigned char*)(0x$interruptHistoryAddress+$interruptEventStride+$interruptEventVectorOffset)
    set `$interrupt2_is_exception = *(unsigned char*)(0x$interruptHistoryAddress+$interruptEventStride+$interruptEventIsExceptionOffset)
    set `$interrupt2_code = *(unsigned long long*)(0x$interruptHistoryAddress+$interruptEventStride+$interruptEventCodeOffset)
    set `$interrupt2_interrupt_count = *(unsigned long long*)(0x$interruptHistoryAddress+$interruptEventStride+$interruptEventInterruptCountOffset)
    set `$interrupt2_exception_count = *(unsigned long long*)(0x$interruptHistoryAddress+$interruptEventStride+$interruptEventExceptionCountOffset)
    set `$exception_seq = *(unsigned int*)(0x$exceptionHistoryAddress+$exceptionEventSeqOffset)
    set `$exception_vector = *(unsigned char*)(0x$exceptionHistoryAddress+$exceptionEventVectorOffset)
    set `$exception_code = *(unsigned long long*)(0x$exceptionHistoryAddress+$exceptionEventCodeOffset)
    set `$exception_interrupt_count = *(unsigned long long*)(0x$exceptionHistoryAddress+$exceptionEventInterruptCountOffset)
    set `$exception_exception_count = *(unsigned long long*)(0x$exceptionHistoryAddress+$exceptionEventExceptionCountOffset)
    printf "AFTER_DESCRIPTOR_DISPATCH\n"
    printf "ACK=%u\n", *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset)
    printf "LAST_OPCODE=%u\n", *(unsigned short*)(0x$statusAddress+$statusLastCommandOpcodeOffset)
    printf "LAST_RESULT=%d\n", *(short*)(0x$statusAddress+$statusLastCommandResultOffset)
    printf "TICKS=%llu\n", *(unsigned long long*)(0x$statusAddress+$statusTicksOffset)
    printf "MAILBOX_OPCODE=%u\n", *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset)
    printf "MAILBOX_SEQ=%u\n", *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset)
    printf "DESCRIPTOR_INIT_BEFORE=%u\n", `$descriptor_init_before
    printf "LOAD_ATTEMPTS_BEFORE=%u\n", `$load_attempts_before
    printf "LOAD_SUCCESSES_BEFORE=%u\n", `$load_successes_before
    printf "DESCRIPTOR_INIT_FINAL=%u\n", *(unsigned int*)(0x$interruptStateAddress+$interruptDescriptorInitCountOffset)
    printf "LOAD_ATTEMPTS_FINAL=%u\n", *(unsigned int*)(0x$interruptStateAddress+$interruptLoadAttemptsOffset)
    printf "LOAD_SUCCESSES_FINAL=%u\n", *(unsigned int*)(0x$interruptStateAddress+$interruptLoadSuccessesOffset)
    printf "DESCRIPTOR_READY_FINAL=%u\n", *(unsigned char*)(0x$interruptStateAddress+$interruptDescriptorReadyOffset)
    printf "DESCRIPTOR_LOADED_FINAL=%u\n", *(unsigned char*)(0x$interruptStateAddress+$interruptDescriptorLoadedOffset)
    printf "LAST_INTERRUPT_VECTOR=%u\n", *(unsigned char*)(0x$interruptStateAddress+$interruptStateLastInterruptVectorOffset)
    printf "INTERRUPT_COUNT=%llu\n", *(unsigned long long*)(0x$interruptStateAddress+$interruptStateInterruptCountOffset)
    printf "LAST_EXCEPTION_VECTOR=%u\n", *(unsigned char*)(0x$interruptStateAddress+$interruptStateLastExceptionVectorOffset)
    printf "EXCEPTION_COUNT=%llu\n", *(unsigned long long*)(0x$interruptStateAddress+$interruptStateExceptionCountOffset)
    printf "LAST_EXCEPTION_CODE=%llu\n", *(unsigned long long*)(0x$interruptStateAddress+$interruptStateLastExceptionCodeOffset)
    printf "INTERRUPT_HISTORY_LEN=%u\n", *(unsigned int*)(0x$interruptStateAddress+$interruptStateInterruptHistoryLenOffset)
    printf "EXCEPTION_HISTORY_LEN=%u\n", *(unsigned int*)(0x$interruptStateAddress+$interruptStateExceptionHistoryLenOffset)
    printf "INTERRUPT_EVENT1_SEQ=%u\n", `$interrupt_seq
    printf "INTERRUPT_EVENT1_VECTOR=%u\n", `$interrupt_vector
    printf "INTERRUPT_EVENT1_IS_EXCEPTION=%u\n", `$interrupt_is_exception
    printf "INTERRUPT_EVENT1_CODE=%llu\n", `$interrupt_code
    printf "INTERRUPT_EVENT1_INTERRUPT_COUNT=%llu\n", `$interrupt_interrupt_count
    printf "INTERRUPT_EVENT1_EXCEPTION_COUNT=%llu\n", `$interrupt_exception_count
    printf "INTERRUPT_EVENT2_SEQ=%u\n", `$interrupt2_seq
    printf "INTERRUPT_EVENT2_VECTOR=%u\n", `$interrupt2_vector
    printf "INTERRUPT_EVENT2_IS_EXCEPTION=%u\n", `$interrupt2_is_exception
    printf "INTERRUPT_EVENT2_CODE=%llu\n", `$interrupt2_code
    printf "INTERRUPT_EVENT2_INTERRUPT_COUNT=%llu\n", `$interrupt2_interrupt_count
    printf "INTERRUPT_EVENT2_EXCEPTION_COUNT=%llu\n", `$interrupt2_exception_count
    printf "EXCEPTION_EVENT1_SEQ=%u\n", `$exception_seq
    printf "EXCEPTION_EVENT1_VECTOR=%u\n", `$exception_vector
    printf "EXCEPTION_EVENT1_CODE=%llu\n", `$exception_code
    printf "EXCEPTION_EVENT1_INTERRUPT_COUNT=%llu\n", `$exception_interrupt_count
    printf "EXCEPTION_EVENT1_EXCEPTION_COUNT=%llu\n", `$exception_exception_count
    quit
  end
  continue
end
continue
end
continue
"@ | Set-Content -Path $gdbScript -Encoding Ascii

$qemuArgs = @("-kernel", $artifact, "-nographic", "-no-reboot", "-no-shutdown", "-serial", "none", "-monitor", "none", "-S", "-gdb", "tcp::$GdbPort")
$qemuProc = Start-Process -FilePath $qemu -ArgumentList $qemuArgs -PassThru -NoNewWindow -RedirectStandardOutput $qemuStdout -RedirectStandardError $qemuStderr
Start-Sleep -Milliseconds 700
$gdbProc = Start-Process -FilePath $gdb -ArgumentList @("-q", "-batch", "-x", $gdbScript) -PassThru -NoNewWindow -RedirectStandardOutput $gdbStdout -RedirectStandardError $gdbStderr

$timedOut = $false
try {
    $null = Wait-Process -Id $gdbProc.Id -Timeout $TimeoutSeconds -ErrorAction Stop
} catch {
    $timedOut = $true
    try { Stop-Process -Id $gdbProc.Id -Force -ErrorAction SilentlyContinue } catch {}
} finally {
    try { Stop-Process -Id $qemuProc.Id -Force -ErrorAction SilentlyContinue } catch {}
}
$hitStart = $false
$hitAfterDescriptorDispatch = $false
$ack = $null
$lastOpcode = $null
$lastResult = $null
$ticks = $null
$mailboxOpcode = $null
$mailboxSeq = $null
$descriptorInitBefore = $null
$loadAttemptsBefore = $null
$loadSuccessesBefore = $null
$descriptorInitFinal = $null
$loadAttemptsFinal = $null
$loadSuccessesFinal = $null
$descriptorReadyFinal = $null
$descriptorLoadedFinal = $null
$lastInterruptVector = $null
$interruptCount = $null
$lastExceptionVector = $null
$exceptionCount = $null
$lastExceptionCode = $null
$interruptHistoryLen = $null
$exceptionHistoryLen = $null
$interruptEvent1Seq = $null
$interruptEvent1Vector = $null
$interruptEvent1IsException = $null
$interruptEvent1Code = $null
$interruptEvent1InterruptCount = $null
$interruptEvent1ExceptionCount = $null
$interruptEvent2Seq = $null
$interruptEvent2Vector = $null
$interruptEvent2IsException = $null
$interruptEvent2Code = $null
$interruptEvent2InterruptCount = $null
$interruptEvent2ExceptionCount = $null
$exceptionEvent1Seq = $null
$exceptionEvent1Vector = $null
$exceptionEvent1Code = $null
$exceptionEvent1InterruptCount = $null
$exceptionEvent1ExceptionCount = $null

if (Test-Path $gdbStdout) {
    $out = Get-Content -Raw $gdbStdout
    $hitStart = $out -match "HIT_START"
    $hitAfterDescriptorDispatch = $out -match "AFTER_DESCRIPTOR_DISPATCH"
    $ack = Extract-IntValue -Text $out -Name "ACK"
    $lastOpcode = Extract-IntValue -Text $out -Name "LAST_OPCODE"
    $lastResult = Extract-IntValue -Text $out -Name "LAST_RESULT"
    $ticks = Extract-IntValue -Text $out -Name "TICKS"
    $mailboxOpcode = Extract-IntValue -Text $out -Name "MAILBOX_OPCODE"
    $mailboxSeq = Extract-IntValue -Text $out -Name "MAILBOX_SEQ"
    $descriptorInitBefore = Extract-IntValue -Text $out -Name "DESCRIPTOR_INIT_BEFORE"
    $loadAttemptsBefore = Extract-IntValue -Text $out -Name "LOAD_ATTEMPTS_BEFORE"
    $loadSuccessesBefore = Extract-IntValue -Text $out -Name "LOAD_SUCCESSES_BEFORE"
    $descriptorInitFinal = Extract-IntValue -Text $out -Name "DESCRIPTOR_INIT_FINAL"
    $loadAttemptsFinal = Extract-IntValue -Text $out -Name "LOAD_ATTEMPTS_FINAL"
    $loadSuccessesFinal = Extract-IntValue -Text $out -Name "LOAD_SUCCESSES_FINAL"
    $descriptorReadyFinal = Extract-IntValue -Text $out -Name "DESCRIPTOR_READY_FINAL"
    $descriptorLoadedFinal = Extract-IntValue -Text $out -Name "DESCRIPTOR_LOADED_FINAL"
    $lastInterruptVector = Extract-IntValue -Text $out -Name "LAST_INTERRUPT_VECTOR"
    $interruptCount = Extract-IntValue -Text $out -Name "INTERRUPT_COUNT"
    $lastExceptionVector = Extract-IntValue -Text $out -Name "LAST_EXCEPTION_VECTOR"
    $exceptionCount = Extract-IntValue -Text $out -Name "EXCEPTION_COUNT"
    $lastExceptionCode = Extract-IntValue -Text $out -Name "LAST_EXCEPTION_CODE"
    $interruptHistoryLen = Extract-IntValue -Text $out -Name "INTERRUPT_HISTORY_LEN"
    $exceptionHistoryLen = Extract-IntValue -Text $out -Name "EXCEPTION_HISTORY_LEN"
    $interruptEvent1Seq = Extract-IntValue -Text $out -Name "INTERRUPT_EVENT1_SEQ"
    $interruptEvent1Vector = Extract-IntValue -Text $out -Name "INTERRUPT_EVENT1_VECTOR"
    $interruptEvent1IsException = Extract-IntValue -Text $out -Name "INTERRUPT_EVENT1_IS_EXCEPTION"
    $interruptEvent1Code = Extract-IntValue -Text $out -Name "INTERRUPT_EVENT1_CODE"
    $interruptEvent1InterruptCount = Extract-IntValue -Text $out -Name "INTERRUPT_EVENT1_INTERRUPT_COUNT"
    $interruptEvent1ExceptionCount = Extract-IntValue -Text $out -Name "INTERRUPT_EVENT1_EXCEPTION_COUNT"
    $interruptEvent2Seq = Extract-IntValue -Text $out -Name "INTERRUPT_EVENT2_SEQ"
    $interruptEvent2Vector = Extract-IntValue -Text $out -Name "INTERRUPT_EVENT2_VECTOR"
    $interruptEvent2IsException = Extract-IntValue -Text $out -Name "INTERRUPT_EVENT2_IS_EXCEPTION"
    $interruptEvent2Code = Extract-IntValue -Text $out -Name "INTERRUPT_EVENT2_CODE"
    $interruptEvent2InterruptCount = Extract-IntValue -Text $out -Name "INTERRUPT_EVENT2_INTERRUPT_COUNT"
    $interruptEvent2ExceptionCount = Extract-IntValue -Text $out -Name "INTERRUPT_EVENT2_EXCEPTION_COUNT"
    $exceptionEvent1Seq = Extract-IntValue -Text $out -Name "EXCEPTION_EVENT1_SEQ"
    $exceptionEvent1Vector = Extract-IntValue -Text $out -Name "EXCEPTION_EVENT1_VECTOR"
    $exceptionEvent1Code = Extract-IntValue -Text $out -Name "EXCEPTION_EVENT1_CODE"
    $exceptionEvent1InterruptCount = Extract-IntValue -Text $out -Name "EXCEPTION_EVENT1_INTERRUPT_COUNT"
    $exceptionEvent1ExceptionCount = Extract-IntValue -Text $out -Name "EXCEPTION_EVENT1_EXCEPTION_COUNT"
}

Write-Output "BAREMETAL_QEMU_AVAILABLE=True"
Write-Output "BAREMETAL_QEMU_BINARY=$qemu"
Write-Output "BAREMETAL_GDB_BINARY=$gdb"
Write-Output "BAREMETAL_NM_BINARY=$nm"
Write-Output "BAREMETAL_QEMU_ARTIFACT=$artifact"
Write-Output "BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_START_ADDR=0x$startAddress"
Write-Output "BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_SPINPAUSE_ADDR=0x$spinPauseAddress"
Write-Output "BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_INTERRUPT_STATE_ADDR=0x$interruptStateAddress"
Write-Output "BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_INTERRUPT_HISTORY_ADDR=0x$interruptHistoryAddress"
Write-Output "BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_EXCEPTION_HISTORY_ADDR=0x$exceptionHistoryAddress"
Write-Output "BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_HIT_START=$hitStart"
Write-Output "BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_HIT_AFTER_DESCRIPTOR_DISPATCH=$hitAfterDescriptorDispatch"
Write-Output "BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_ACK=$ack"
Write-Output "BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_LAST_OPCODE=$lastOpcode"
Write-Output "BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_LAST_RESULT=$lastResult"
Write-Output "BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_TICKS=$ticks"
Write-Output "BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_MAILBOX_OPCODE=$mailboxOpcode"
Write-Output "BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_MAILBOX_SEQ=$mailboxSeq"
Write-Output "BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_DESCRIPTOR_INIT_BEFORE=$descriptorInitBefore"
Write-Output "BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_LOAD_ATTEMPTS_BEFORE=$loadAttemptsBefore"
Write-Output "BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_LOAD_SUCCESSES_BEFORE=$loadSuccessesBefore"
Write-Output "BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_DESCRIPTOR_INIT_FINAL=$descriptorInitFinal"
Write-Output "BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_LOAD_ATTEMPTS_FINAL=$loadAttemptsFinal"
Write-Output "BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_LOAD_SUCCESSES_FINAL=$loadSuccessesFinal"
Write-Output "BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_DESCRIPTOR_READY_FINAL=$descriptorReadyFinal"
Write-Output "BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_DESCRIPTOR_LOADED_FINAL=$descriptorLoadedFinal"
Write-Output "BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_LAST_INTERRUPT_VECTOR=$lastInterruptVector"
Write-Output "BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_INTERRUPT_COUNT=$interruptCount"
Write-Output "BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_LAST_EXCEPTION_VECTOR=$lastExceptionVector"
Write-Output "BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_EXCEPTION_COUNT=$exceptionCount"
Write-Output "BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_LAST_EXCEPTION_CODE=$lastExceptionCode"
Write-Output "BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_INTERRUPT_HISTORY_LEN=$interruptHistoryLen"
Write-Output "BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_EXCEPTION_HISTORY_LEN=$exceptionHistoryLen"
Write-Output "BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_INTERRUPT_EVENT1_SEQ=$interruptEvent1Seq"
Write-Output "BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_INTERRUPT_EVENT1_VECTOR=$interruptEvent1Vector"
Write-Output "BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_INTERRUPT_EVENT1_IS_EXCEPTION=$interruptEvent1IsException"
Write-Output "BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_INTERRUPT_EVENT1_CODE=$interruptEvent1Code"
Write-Output "BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_INTERRUPT_EVENT1_INTERRUPT_COUNT=$interruptEvent1InterruptCount"
Write-Output "BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_INTERRUPT_EVENT1_EXCEPTION_COUNT=$interruptEvent1ExceptionCount"
Write-Output "BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_INTERRUPT_EVENT2_SEQ=$interruptEvent2Seq"
Write-Output "BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_INTERRUPT_EVENT2_VECTOR=$interruptEvent2Vector"
Write-Output "BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_INTERRUPT_EVENT2_IS_EXCEPTION=$interruptEvent2IsException"
Write-Output "BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_INTERRUPT_EVENT2_CODE=$interruptEvent2Code"
Write-Output "BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_INTERRUPT_EVENT2_INTERRUPT_COUNT=$interruptEvent2InterruptCount"
Write-Output "BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_INTERRUPT_EVENT2_EXCEPTION_COUNT=$interruptEvent2ExceptionCount"
Write-Output "BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_EXCEPTION_EVENT1_SEQ=$exceptionEvent1Seq"
Write-Output "BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_EXCEPTION_EVENT1_VECTOR=$exceptionEvent1Vector"
Write-Output "BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_EXCEPTION_EVENT1_CODE=$exceptionEvent1Code"
Write-Output "BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_EXCEPTION_EVENT1_INTERRUPT_COUNT=$exceptionEvent1InterruptCount"
Write-Output "BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_EXCEPTION_EVENT1_EXCEPTION_COUNT=$exceptionEvent1ExceptionCount"
Write-Output "BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_GDB_STDOUT=$gdbStdout"
Write-Output "BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_GDB_STDERR=$gdbStderr"
Write-Output "BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_QEMU_STDOUT=$qemuStdout"
Write-Output "BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_QEMU_STDERR=$qemuStderr"
Write-Output "BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_TIMED_OUT=$timedOut"

$pass = (
    $hitStart -and
    $hitAfterDescriptorDispatch -and
    (-not $timedOut) -and
    $ack -eq 8 -and
    $lastOpcode -eq $triggerExceptionOpcode -and
    $lastResult -eq 0 -and
    $ticks -gt 0 -and
    $mailboxOpcode -eq $triggerExceptionOpcode -and
    $mailboxSeq -eq 8 -and
    $descriptorInitBefore -ge 1 -and
    $descriptorInitFinal -eq ($descriptorInitBefore + 1) -and
    $loadAttemptsFinal -eq ($loadAttemptsBefore + 1) -and
    $loadSuccessesFinal -eq ($loadSuccessesBefore + 1) -and
    $descriptorReadyFinal -eq 1 -and
    $descriptorLoadedFinal -eq 1 -and
    $lastInterruptVector -eq $exceptionVector -and
    $interruptCount -eq 2 -and
    $lastExceptionVector -eq $exceptionVector -and
    $exceptionCount -eq 1 -and
    $lastExceptionCode -eq $exceptionCode -and
    $interruptHistoryLen -eq 2 -and
    $exceptionHistoryLen -eq 1 -and
    $interruptEvent1Seq -eq 1 -and
    $interruptEvent1Vector -eq $interruptVector -and
    $interruptEvent1IsException -eq 0 -and
    $interruptEvent1Code -eq 0 -and
    $interruptEvent1InterruptCount -eq 1 -and
    $interruptEvent1ExceptionCount -eq 0 -and
    $interruptEvent2Seq -eq 2 -and
    $interruptEvent2Vector -eq $exceptionVector -and
    $interruptEvent2IsException -eq 1 -and
    $interruptEvent2Code -eq $exceptionCode -and
    $interruptEvent2InterruptCount -eq 2 -and
    $interruptEvent2ExceptionCount -eq 1 -and
    $exceptionEvent1Seq -eq 1 -and
    $exceptionEvent1Vector -eq $exceptionVector -and
    $exceptionEvent1Code -eq $exceptionCode -and
    $exceptionEvent1InterruptCount -eq 2 -and
    $exceptionEvent1ExceptionCount -eq 1
)

if ($pass) {
    Write-Output "BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE=pass"
    exit 0
}

Write-Output "BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE=fail"
if (Test-Path $gdbStdout) { Get-Content -Path $gdbStdout -Tail 160 }
if (Test-Path $gdbStderr) { Get-Content -Path $gdbStderr -Tail 160 }
if (Test-Path $qemuStderr) { Get-Content -Path $qemuStderr -Tail 160 }
exit 1
