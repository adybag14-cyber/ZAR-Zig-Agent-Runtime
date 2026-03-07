param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 30,
    [int] $GdbPort = 0
)

$ErrorActionPreference = "Stop"

$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$releaseDir = Join-Path $repo "release"
$prerequisiteScript = Join-Path $PSScriptRoot "baremetal-qemu-descriptor-bootdiag-probe-check.ps1"
$artifact = Join-Path $releaseDir "openclaw-zig-baremetal-pvh-descriptor-bootdiag-probe.elf"
$runStamp = [DateTime]::UtcNow.ToString("yyyyMMddHHmmssfff")
$gdbScript = Join-Path $releaseDir "qemu-vector-counter-reset-probe-$runStamp.gdb"
$gdbStdout = Join-Path $releaseDir "qemu-vector-counter-reset-probe-$runStamp.gdb.stdout.log"
$gdbStderr = Join-Path $releaseDir "qemu-vector-counter-reset-probe-$runStamp.gdb.stderr.log"
$qemuStdout = Join-Path $releaseDir "qemu-vector-counter-reset-probe-$runStamp.qemu.stdout.log"
$qemuStderr = Join-Path $releaseDir "qemu-vector-counter-reset-probe-$runStamp.qemu.stderr.log"

$triggerInterruptOpcode = 7
$resetInterruptCountersOpcode = 8
$resetExceptionCountersOpcode = 11
$triggerExceptionOpcode = 12
$resetVectorCountersOpcode = 15

$interruptVectorA = 10
$interruptVectorB = 200
$exceptionVector = 14
$exceptionCode = 43981

$interruptCountStride = 8
$interruptVectorAOffset = $interruptVectorA * $interruptCountStride
$interruptVectorBOffset = $interruptVectorB * $interruptCountStride
$exceptionVectorOffset = $exceptionVector * $interruptCountStride

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
$interruptStateInterruptCountOffset = 16
$interruptStateLastExceptionVectorOffset = 24
$interruptStateExceptionCountOffset = 32
$interruptStateLastExceptionCodeOffset = 40

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

function Resolve-FreeTcpPort {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    try {
        $listener.Start()
        return ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
    }
    finally {
        $listener.Stop()
    }
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
    if ($SkipBuild -and -not (Test-Path $artifact)) { throw "Vector counter reset prerequisite artifact not found at $artifact and -SkipBuild was supplied." }
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

if ($GdbPort -le 0) {
    $GdbPort = Resolve-FreeTcpPort
}

if ($null -eq $qemu) {
    Write-Output "BAREMETAL_QEMU_AVAILABLE=False"
    Write-Output "BAREMETAL_QEMU_VECTOR_COUNTER_RESET_PROBE=skipped"
    exit 0
}
if ($null -eq $gdb) {
    Write-Output "BAREMETAL_QEMU_AVAILABLE=True"
    Write-Output "BAREMETAL_QEMU_BINARY=$qemu"
    Write-Output "BAREMETAL_GDB_AVAILABLE=False"
    Write-Output "BAREMETAL_QEMU_VECTOR_COUNTER_RESET_PROBE=skipped"
    exit 0
}
if ($null -eq $nm) {
    Write-Output "BAREMETAL_QEMU_AVAILABLE=True"
    Write-Output "BAREMETAL_QEMU_BINARY=$qemu"
    Write-Output "BAREMETAL_GDB_BINARY=$gdb"
    Write-Output "BAREMETAL_NM_AVAILABLE=False"
    Write-Output "BAREMETAL_QEMU_VECTOR_COUNTER_RESET_PROBE=skipped"
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
    Write-Output "BAREMETAL_QEMU_VECTOR_COUNTER_RESET_PROBE=skipped"
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

@"
set pagination off
set confirm off
set `$stage = 0
set `$pre_interrupt_count = 0
set `$pre_exception_count = 0
set `$pre_last_interrupt_vector = 0
set `$pre_last_exception_vector = 0
set `$pre_last_exception_code = 0
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
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $resetInterruptCountersOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = 1
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = 0
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = 0
    set `$stage = 1
  end
  continue
end
if `$stage == 1
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == 1 && *(unsigned long long*)(0x$interruptStateAddress+$interruptStateInterruptCountOffset) == 0
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $resetExceptionCountersOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = 2
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = 0
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = 0
    set `$stage = 2
  end
  continue
end
if `$stage == 2
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == 2 && *(unsigned long long*)(0x$interruptStateAddress+$interruptStateExceptionCountOffset) == 0
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $resetVectorCountersOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = 3
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = 0
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = 0
    set `$stage = 3
  end
  continue
end
if `$stage == 3
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == 3 && *(unsigned long long*)(0x$interruptVectorCountsAddress+$interruptVectorAOffset) == 0 && *(unsigned long long*)(0x$interruptVectorCountsAddress+$interruptVectorBOffset) == 0 && *(unsigned long long*)(0x$interruptVectorCountsAddress+$exceptionVectorOffset) == 0 && *(unsigned long long*)(0x$exceptionVectorCountsAddress+$interruptVectorAOffset) == 0 && *(unsigned long long*)(0x$exceptionVectorCountsAddress+$exceptionVectorOffset) == 0
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $triggerInterruptOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = 4
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = $interruptVectorA
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = 0
    set `$stage = 4
  end
  continue
end
if `$stage == 4
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == 4 && *(unsigned long long*)(0x$interruptStateAddress+$interruptStateInterruptCountOffset) == 1 && *(unsigned long long*)(0x$interruptStateAddress+$interruptStateExceptionCountOffset) == 1 && *(unsigned long long*)(0x$interruptVectorCountsAddress+$interruptVectorAOffset) == 1 && *(unsigned long long*)(0x$exceptionVectorCountsAddress+$interruptVectorAOffset) == 1
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $triggerInterruptOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = 5
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = $interruptVectorA
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = 0
    set `$stage = 5
  end
  continue
end
if `$stage == 5
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == 5 && *(unsigned long long*)(0x$interruptStateAddress+$interruptStateInterruptCountOffset) == 2 && *(unsigned long long*)(0x$interruptStateAddress+$interruptStateExceptionCountOffset) == 2 && *(unsigned long long*)(0x$interruptVectorCountsAddress+$interruptVectorAOffset) == 2 && *(unsigned long long*)(0x$exceptionVectorCountsAddress+$interruptVectorAOffset) == 2
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $triggerInterruptOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = 6
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = $interruptVectorB
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = 0
    set `$stage = 6
  end
  continue
end
if `$stage == 6
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == 6 && *(unsigned long long*)(0x$interruptStateAddress+$interruptStateInterruptCountOffset) == 3 && *(unsigned long long*)(0x$interruptStateAddress+$interruptStateExceptionCountOffset) == 2 && *(unsigned long long*)(0x$interruptVectorCountsAddress+$interruptVectorBOffset) == 1
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $triggerExceptionOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = 7
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = $exceptionVector
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = $exceptionCode
    set `$stage = 7
  end
  continue
end
if `$stage == 7
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == 7 && *(unsigned long long*)(0x$interruptStateAddress+$interruptStateInterruptCountOffset) == 4 && *(unsigned long long*)(0x$interruptStateAddress+$interruptStateExceptionCountOffset) == 3 && *(unsigned long long*)(0x$interruptVectorCountsAddress+$exceptionVectorOffset) == 1 && *(unsigned long long*)(0x$exceptionVectorCountsAddress+$exceptionVectorOffset) == 1
    set `$pre_interrupt_count = *(unsigned long long*)(0x$interruptStateAddress+$interruptStateInterruptCountOffset)
    set `$pre_exception_count = *(unsigned long long*)(0x$interruptStateAddress+$interruptStateExceptionCountOffset)
    set `$pre_last_interrupt_vector = *(unsigned char*)(0x$interruptStateAddress+$interruptStateLastInterruptVectorOffset)
    set `$pre_last_exception_vector = *(unsigned char*)(0x$interruptStateAddress+$interruptStateLastExceptionVectorOffset)
    set `$pre_last_exception_code = *(unsigned long long*)(0x$interruptStateAddress+$interruptStateLastExceptionCodeOffset)
    set *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset) = $resetVectorCountersOpcode
    set *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset) = 8
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg0Offset) = 0
    set *(unsigned long long*)(0x$commandMailboxAddress+$commandArg1Offset) = 0
    set `$stage = 8
  end
  continue
end
if `$stage == 8
  if *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset) == 8 && *(unsigned long long*)(0x$interruptVectorCountsAddress+$interruptVectorAOffset) == 0 && *(unsigned long long*)(0x$interruptVectorCountsAddress+$interruptVectorBOffset) == 0 && *(unsigned long long*)(0x$interruptVectorCountsAddress+$exceptionVectorOffset) == 0 && *(unsigned long long*)(0x$exceptionVectorCountsAddress+$interruptVectorAOffset) == 0 && *(unsigned long long*)(0x$exceptionVectorCountsAddress+$exceptionVectorOffset) == 0 && *(unsigned long long*)(0x$interruptStateAddress+$interruptStateInterruptCountOffset) == `$pre_interrupt_count && *(unsigned long long*)(0x$interruptStateAddress+$interruptStateExceptionCountOffset) == `$pre_exception_count
    printf "AFTER_VECTOR_COUNTER_RESET\n"
    printf "ACK=%u\n", *(unsigned int*)(0x$statusAddress+$statusCommandSeqAckOffset)
    printf "LAST_OPCODE=%u\n", *(unsigned short*)(0x$statusAddress+$statusLastCommandOpcodeOffset)
    printf "LAST_RESULT=%d\n", *(short*)(0x$statusAddress+$statusLastCommandResultOffset)
    printf "TICKS=%llu\n", *(unsigned long long*)(0x$statusAddress+$statusTicksOffset)
    printf "MAILBOX_OPCODE=%u\n", *(unsigned short*)(0x$commandMailboxAddress+$commandOpcodeOffset)
    printf "MAILBOX_SEQ=%u\n", *(unsigned int*)(0x$commandMailboxAddress+$commandSeqOffset)
    printf "PRE_INTERRUPT_COUNT=%llu\n", `$pre_interrupt_count
    printf "PRE_EXCEPTION_COUNT=%llu\n", `$pre_exception_count
    printf "PRE_LAST_INTERRUPT_VECTOR=%u\n", `$pre_last_interrupt_vector
    printf "PRE_LAST_EXCEPTION_VECTOR=%u\n", `$pre_last_exception_vector
    printf "PRE_LAST_EXCEPTION_CODE=%llu\n", `$pre_last_exception_code
    printf "POST_INTERRUPT_COUNT=%llu\n", *(unsigned long long*)(0x$interruptStateAddress+$interruptStateInterruptCountOffset)
    printf "POST_EXCEPTION_COUNT=%llu\n", *(unsigned long long*)(0x$interruptStateAddress+$interruptStateExceptionCountOffset)
    printf "POST_LAST_INTERRUPT_VECTOR=%u\n", *(unsigned char*)(0x$interruptStateAddress+$interruptStateLastInterruptVectorOffset)
    printf "POST_LAST_EXCEPTION_VECTOR=%u\n", *(unsigned char*)(0x$interruptStateAddress+$interruptStateLastExceptionVectorOffset)
    printf "POST_LAST_EXCEPTION_CODE=%llu\n", *(unsigned long long*)(0x$interruptStateAddress+$interruptStateLastExceptionCodeOffset)
    printf "PRE_INT_VECTOR10=%llu\n", 2
    printf "PRE_INT_VECTOR200=%llu\n", 1
    printf "PRE_INT_VECTOR14=%llu\n", 1
    printf "PRE_EXC_VECTOR10=%llu\n", 2
    printf "PRE_EXC_VECTOR14=%llu\n", 1
    printf "POST_INT_VECTOR10=%llu\n", *(unsigned long long*)(0x$interruptVectorCountsAddress+$interruptVectorAOffset)
    printf "POST_INT_VECTOR200=%llu\n", *(unsigned long long*)(0x$interruptVectorCountsAddress+$interruptVectorBOffset)
    printf "POST_INT_VECTOR14=%llu\n", *(unsigned long long*)(0x$interruptVectorCountsAddress+$exceptionVectorOffset)
    printf "POST_EXC_VECTOR10=%llu\n", *(unsigned long long*)(0x$exceptionVectorCountsAddress+$interruptVectorAOffset)
    printf "POST_EXC_VECTOR14=%llu\n", *(unsigned long long*)(0x$exceptionVectorCountsAddress+$exceptionVectorOffset)
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
    if (-not $gdbProc.WaitForExit($TimeoutSeconds * 1000)) {
        $timedOut = $true
        try { Stop-Process -Id $gdbProc.Id -Force -ErrorAction SilentlyContinue } catch {}
        throw "GDB timed out after $TimeoutSeconds seconds"
    }
    $gdbProc.Refresh()
    $gdbExitCode = if ($null -eq $gdbProc.ExitCode) { 0 } else { [int]$gdbProc.ExitCode }
    if ($gdbExitCode -ne 0) {
        $stderr = if (Test-Path $gdbStderr) { Get-Content -Raw $gdbStderr } else { "" }
        $stdout = if (Test-Path $gdbStdout) { Get-Content -Raw $gdbStdout } else { "" }
        throw "GDB exited with code $gdbExitCode`nSTDOUT:`n$stdout`nSTDERR:`n$stderr"
    }
}
finally {
    if ($null -ne $gdbProc -and -not $gdbProc.HasExited) {
        try { Stop-Process -Id $gdbProc.Id -Force -ErrorAction SilentlyContinue } catch {}
    }
    if ($null -ne $qemuProc -and -not $qemuProc.HasExited) {
        try { Stop-Process -Id $qemuProc.Id -Force -ErrorAction SilentlyContinue } catch {}
    }
}

$stdout = if (Test-Path $gdbStdout) { Get-Content -Raw $gdbStdout } else { "" }
$stderr = if (Test-Path $gdbStderr) { Get-Content -Raw $gdbStderr } else { "" }

Write-Output "BAREMETAL_QEMU_AVAILABLE=True"
Write-Output "BAREMETAL_QEMU_BINARY=$qemu"
Write-Output "BAREMETAL_GDB_BINARY=$gdb"
Write-Output "BAREMETAL_NM_BINARY=$nm"
Write-Output "BAREMETAL_QEMU_VECTOR_COUNTER_RESET_ARTIFACT=$artifact"
Write-Output "BAREMETAL_QEMU_VECTOR_COUNTER_RESET_START_ADDR=0x$startAddress"
Write-Output "BAREMETAL_QEMU_VECTOR_COUNTER_RESET_SPINPAUSE_ADDR=0x$spinPauseAddress"
Write-Output "BAREMETAL_QEMU_VECTOR_COUNTER_RESET_STATUS_ADDR=0x$statusAddress"
Write-Output "BAREMETAL_QEMU_VECTOR_COUNTER_RESET_MAILBOX_ADDR=0x$commandMailboxAddress"
Write-Output "BAREMETAL_QEMU_VECTOR_COUNTER_RESET_INTERRUPT_STATE_ADDR=0x$interruptStateAddress"
Write-Output "BAREMETAL_QEMU_VECTOR_COUNTER_RESET_INTERRUPT_VECTOR_COUNTS_ADDR=0x$interruptVectorCountsAddress"
Write-Output "BAREMETAL_QEMU_VECTOR_COUNTER_RESET_EXCEPTION_VECTOR_COUNTS_ADDR=0x$exceptionVectorCountsAddress"
Write-Output "BAREMETAL_QEMU_VECTOR_COUNTER_RESET_TIMED_OUT=$timedOut"
Write-Output "BAREMETAL_QEMU_VECTOR_COUNTER_RESET_GDB_STDOUT=$gdbStdout"
Write-Output "BAREMETAL_QEMU_VECTOR_COUNTER_RESET_GDB_STDERR=$gdbStderr"
Write-Output "BAREMETAL_QEMU_VECTOR_COUNTER_RESET_QEMU_STDOUT=$qemuStdout"
Write-Output "BAREMETAL_QEMU_VECTOR_COUNTER_RESET_QEMU_STDERR=$qemuStderr"

if ($stdout -notmatch 'HIT_START' -or $stdout -notmatch 'AFTER_VECTOR_COUNTER_RESET') {
    Write-Output $stdout
    if ($stderr) { Write-Output $stderr }
    throw "Vector counter reset probe did not reach the expected GDB checkpoints"
}

$expectedInts = @{
    "ACK" = 8
    "LAST_OPCODE" = $resetVectorCountersOpcode
    "LAST_RESULT" = 0
    "MAILBOX_OPCODE" = $resetVectorCountersOpcode
    "MAILBOX_SEQ" = 8
    "PRE_INTERRUPT_COUNT" = 4
    "PRE_EXCEPTION_COUNT" = 3
    "PRE_LAST_INTERRUPT_VECTOR" = $exceptionVector
    "PRE_LAST_EXCEPTION_VECTOR" = $exceptionVector
    "PRE_LAST_EXCEPTION_CODE" = $exceptionCode
    "POST_INTERRUPT_COUNT" = 4
    "POST_EXCEPTION_COUNT" = 3
    "POST_LAST_INTERRUPT_VECTOR" = $exceptionVector
    "POST_LAST_EXCEPTION_VECTOR" = $exceptionVector
    "POST_LAST_EXCEPTION_CODE" = $exceptionCode
    "PRE_INT_VECTOR10" = 2
    "PRE_INT_VECTOR200" = 1
    "PRE_INT_VECTOR14" = 1
    "PRE_EXC_VECTOR10" = 2
    "PRE_EXC_VECTOR14" = 1
    "POST_INT_VECTOR10" = 0
    "POST_INT_VECTOR200" = 0
    "POST_INT_VECTOR14" = 0
    "POST_EXC_VECTOR10" = 0
    "POST_EXC_VECTOR14" = 0
}

foreach ($entry in $expectedInts.GetEnumerator()) {
    $actual = Extract-IntValue -Text $stdout -Name $entry.Key
    if ($null -eq $actual) {
        throw "Missing expected output line for $($entry.Key)"
    }
    if ($actual -ne $entry.Value) {
        throw "Unexpected value for $($entry.Key): expected $($entry.Value), got $actual"
    }
    Write-Output "BAREMETAL_QEMU_VECTOR_COUNTER_RESET_$($entry.Key)=$actual"
}

$ticks = Extract-IntValue -Text $stdout -Name "TICKS"
if ($null -eq $ticks) {
    throw "Missing expected output line for TICKS"
}
if ($ticks -lt 8) {
    throw "Unexpected TICKS value: expected at least 8, got $ticks"
}
Write-Output "BAREMETAL_QEMU_VECTOR_COUNTER_RESET_TICKS=$ticks"
Write-Output "BAREMETAL_QEMU_VECTOR_COUNTER_RESET_PROBE=pass"
