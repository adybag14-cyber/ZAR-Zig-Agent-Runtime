# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 60,
    [int] $GdbPort = 0
)

$ErrorActionPreference = "Stop"

$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$releaseDir = Join-Path $repo "release"
$runStamp = [DateTime]::UtcNow.ToString("yyyyMMddHHmmssfff")

$acpiMagic = 0x4f434150
$apiVersion = 2
$expectedExitCode = 0x7C
$expectedMaskedVector = 200

$acpiMagicOffset = 0
$acpiApiVersionOffset = 4
$acpiPresentOffset = 6
$acpiRevisionOffset = 7
$acpiTableCountOffset = 14
$acpiLapicCountOffset = 16
$acpiIoApicCountOffset = 18
$acpiSciInterruptOffset = 20
$acpiPmTimerBlockOffset = 24
$acpiFlagsOffset = 28
$acpiRsdpAddrOffset = 32
$timerEnabledOffset = 0
$timerPendingWakeCountOffset = 2
$timerDispatchCountOffset = 8
$timerLastInterruptCountOffset = 24
$timerTickQuantumOffset = 40
$interruptDescriptorReadyOffset = 0
$interruptDescriptorLoadedOffset = 1
$interruptLastVectorOffset = 2
$interruptCountOffset = 16
$interruptHistoryLenOffset = 56

function Resolve-ZigExecutable {
    $default = "C:\Users\Ady\Documents\toolchains\zig-master\current\zig.exe"
    if ($env:OPENCLAW_ZIG_BIN -and $env:OPENCLAW_ZIG_BIN.Trim().Length -gt 0) {
        if (-not (Test-Path $env:OPENCLAW_ZIG_BIN)) { throw "OPENCLAW_ZIG_BIN is set but not found: $($env:OPENCLAW_ZIG_BIN)" }
        return $env:OPENCLAW_ZIG_BIN
    }
    $cmd = Get-Command zig -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Path) { return $cmd.Path }
    if (Test-Path $default) { return $default }
    throw "Zig executable not found. Set OPENCLAW_ZIG_BIN or ensure zig is on PATH."
}

function Resolve-PreferredExecutable {
    param([string[]] $Candidates)
    foreach ($name in $Candidates) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd -and $cmd.Path) { return $cmd.Path }
        if (Test-Path $name) { return (Resolve-Path $name).Path }
    }
    return $null
}

function Resolve-QemuExecutable { return Resolve-PreferredExecutable @("qemu-system-i386", "qemu-system-i386.exe", "C:\Program Files\qemu\qemu-system-i386.exe") }
function Resolve-GdbExecutable { return Resolve-PreferredExecutable @("gdb", "gdb.exe") }
function Resolve-NmExecutable { return Resolve-PreferredExecutable @("llvm-nm", "llvm-nm.exe", "nm", "nm.exe", "C:\Users\Ady\Documents\starpro\tooling\emsdk\upstream\bin\llvm-nm.exe") }

function Resolve-FreeTcpPort {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    try {
        $listener.Start()
        return ([System.Net.IPEndPoint] $listener.LocalEndpoint).Port
    } finally {
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

function Remove-PathWithRetry {
    param([string] $Path)
    if (-not (Test-Path $Path)) { return }
    for ($attempt = 0; $attempt -lt 5; $attempt += 1) {
        try {
            Remove-Item -Force -ErrorAction Stop $Path
            return
        } catch {
            if ($attempt -ge 4) { throw }
            Start-Sleep -Milliseconds 100
        }
    }
}

Set-Location $repo
New-Item -ItemType Directory -Force -Path $releaseDir | Out-Null

$zig = Resolve-ZigExecutable
$qemu = Resolve-QemuExecutable
$gdb = Resolve-GdbExecutable
$nm = Resolve-NmExecutable

if ($null -eq $qemu -or $null -eq $gdb -or $null -eq $nm) {
    Write-Output "BAREMETAL_I386_QEMU_AVAILABLE=$([bool]($null -ne $qemu))"
    Write-Output "BAREMETAL_I386_GDB_AVAILABLE=$([bool]($null -ne $gdb))"
    Write-Output "BAREMETAL_I386_NM_AVAILABLE=$([bool]($null -ne $nm))"
    Write-Output "BAREMETAL_I386_PLATFORM_PROBE=skipped"
    return
}

if ($GdbPort -le 0) { $GdbPort = Resolve-FreeTcpPort }

$gdbScript = Join-Path $releaseDir "qemu-i386-platform-probe-$runStamp.gdb"
$gdbStdout = Join-Path $releaseDir "qemu-i386-platform-probe-$runStamp.gdb.stdout.log"
$gdbStderr = Join-Path $releaseDir "qemu-i386-platform-probe-$runStamp.gdb.stderr.log"
$qemuStdout = Join-Path $releaseDir "qemu-i386-platform-probe-$runStamp.qemu.stdout.log"
$qemuStderr = Join-Path $releaseDir "qemu-i386-platform-probe-$runStamp.qemu.stderr.log"

if (-not $SkipBuild) {
    & $zig build baremetal-i386 -Doptimize=Debug -Dbaremetal-i386-platform-probe=true --summary all
    if ($LASTEXITCODE -ne 0) { throw "zig build baremetal-i386 platform probe failed with exit code $LASTEXITCODE" }
}

$artifactCandidates = @(
    (Join-Path $repo 'zig-out\bin\openclaw-zig-baremetal-i386.elf'),
    (Join-Path $repo 'zig-out\openclaw-zig-baremetal-i386.elf'),
    (Join-Path $repo 'zig-out/openclaw-zig-baremetal-i386.elf')
)
$artifact = $null
foreach ($candidate in $artifactCandidates) {
    if (Test-Path $candidate) {
        $artifact = (Resolve-Path $candidate).Path
        break
    }
}
if ($null -eq $artifact) { throw 'i386 platform-probe artifact not found after build.' }

$symbolOutput = & $nm $artifact
if ($LASTEXITCODE -ne 0 -or $null -eq $symbolOutput -or $symbolOutput.Count -eq 0) {
    throw "Failed to resolve symbol table from $artifact using $nm"
}

$qemuExitAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[tT]\sbaremetal_main\.qemuExit$' -SymbolName "baremetal_main.qemuExit"
$acpiStateAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[dDbB]\sbaremetal\.acpi\.state$' -SymbolName "baremetal.acpi.state"
$timerStateAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[dDbB]\sbaremetal_main\.timer_state$' -SymbolName "baremetal_main.timer_state"
$interruptStateAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[dDbB]\sbaremetal\.x86_bootstrap\.interrupt_state$' -SymbolName "baremetal.x86_bootstrap.interrupt_state"
$maskedInterruptIgnoredCountAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[dDbB]\sbaremetal\.x86_bootstrap\.masked_interrupt_ignored_count$' -SymbolName "baremetal.x86_bootstrap.masked_interrupt_ignored_count"
$lastMaskedInterruptVectorAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[dDbB]\sbaremetal\.x86_bootstrap\.last_masked_interrupt_vector$' -SymbolName "baremetal.x86_bootstrap.last_masked_interrupt_vector"
$artifactForGdb = $artifact.Replace('\', '/')

Remove-PathWithRetry $gdbStdout
Remove-PathWithRetry $gdbStderr
Remove-PathWithRetry $qemuStdout
Remove-PathWithRetry $qemuStderr

$gdbTemplate = @'
set pagination off
set confirm off
set remotecache off
file __ARTIFACT__
handle SIGQUIT nostop noprint pass
target remote :__GDBPORT__
break *0x__QEMU_EXIT__
commands
  silent
  printf "QEMU_EXIT_CODE_STACK=%u\n", *(unsigned int*)($esp + 4)
  printf "QEMU_EXIT_CODE_EAX=%u\n", (unsigned int)($eax & 0xff)
  printf "QEMU_EXIT_CODE_ECX=%u\n", (unsigned int)($ecx & 0xff)
  printf "ACPI_MAGIC=%u\n", *(unsigned int*)(__ACPI_STATE_ADDR__ + __ACPI_MAGIC_OFFSET__)
  printf "ACPI_API_VERSION=%u\n", *(unsigned short*)(__ACPI_STATE_ADDR__ + __ACPI_API_VERSION_OFFSET__)
  printf "ACPI_PRESENT=%u\n", *(unsigned char*)(__ACPI_STATE_ADDR__ + __ACPI_PRESENT_OFFSET__)
  printf "ACPI_REVISION=%u\n", *(unsigned char*)(__ACPI_STATE_ADDR__ + __ACPI_REVISION_OFFSET__)
  printf "ACPI_TABLE_COUNT=%u\n", *(unsigned short*)(__ACPI_STATE_ADDR__ + __ACPI_TABLE_COUNT_OFFSET__)
  printf "ACPI_LAPIC_COUNT=%u\n", *(unsigned short*)(__ACPI_STATE_ADDR__ + __ACPI_LAPIC_COUNT_OFFSET__)
  printf "ACPI_IOAPIC_COUNT=%u\n", *(unsigned short*)(__ACPI_STATE_ADDR__ + __ACPI_IOAPIC_COUNT_OFFSET__)
  printf "ACPI_SCI_INTERRUPT=%u\n", *(unsigned short*)(__ACPI_STATE_ADDR__ + __ACPI_SCI_INTERRUPT_OFFSET__)
  printf "ACPI_PM_TIMER_BLOCK=%u\n", *(unsigned int*)(__ACPI_STATE_ADDR__ + __ACPI_PM_TIMER_BLOCK_OFFSET__)
  printf "ACPI_FLAGS=%u\n", *(unsigned int*)(__ACPI_STATE_ADDR__ + __ACPI_FLAGS_OFFSET__)
  printf "ACPI_RSDP_ADDR=%u\n", *(unsigned int*)(__ACPI_STATE_ADDR__ + __ACPI_RSDP_ADDR_OFFSET__)
  printf "TIMER_ENABLED=%u\n", *(unsigned char*)(__TIMER_STATE_ADDR__ + __TIMER_ENABLED_OFFSET__)
  printf "TIMER_PENDING_WAKE_COUNT=%u\n", *(unsigned short*)(__TIMER_STATE_ADDR__ + __TIMER_PENDING_WAKE_COUNT_OFFSET__)
  printf "TIMER_DISPATCH_COUNT=%u\n", *(unsigned long long*)(__TIMER_STATE_ADDR__ + __TIMER_DISPATCH_COUNT_OFFSET__)
  printf "TIMER_LAST_INTERRUPT_COUNT=%u\n", *(unsigned long long*)(__TIMER_STATE_ADDR__ + __TIMER_LAST_INTERRUPT_COUNT_OFFSET__)
  printf "TIMER_TICK_QUANTUM=%u\n", *(unsigned int*)(__TIMER_STATE_ADDR__ + __TIMER_TICK_QUANTUM_OFFSET__)
  printf "INTERRUPT_DESCRIPTOR_READY=%u\n", *(unsigned char*)(__INTERRUPT_STATE_ADDR__ + __INTERRUPT_DESCRIPTOR_READY_OFFSET__)
  printf "INTERRUPT_DESCRIPTOR_LOADED=%u\n", *(unsigned char*)(__INTERRUPT_STATE_ADDR__ + __INTERRUPT_DESCRIPTOR_LOADED_OFFSET__)
  printf "INTERRUPT_LAST_VECTOR=%u\n", *(unsigned char*)(__INTERRUPT_STATE_ADDR__ + __INTERRUPT_LAST_VECTOR_OFFSET__)
  printf "INTERRUPT_COUNT=%u\n", *(unsigned long long*)(__INTERRUPT_STATE_ADDR__ + __INTERRUPT_COUNT_OFFSET__)
  printf "INTERRUPT_HISTORY_LEN=%u\n", *(unsigned int*)(__INTERRUPT_STATE_ADDR__ + __INTERRUPT_HISTORY_LEN_OFFSET__)
  printf "INTERRUPT_MASK_IGNORED_COUNT=%u\n", *(unsigned long long*)(__INTERRUPT_MASK_IGNORED_COUNT_ADDR__)
  printf "INTERRUPT_LAST_MASKED_VECTOR=%u\n", *(unsigned char*)(__INTERRUPT_LAST_MASKED_VECTOR_ADDR__)
  quit
end
continue
'@

$gdbScriptContent = $gdbTemplate `
    -replace '__ARTIFACT__', $artifactForGdb `
    -replace '__GDBPORT__', $GdbPort `
    -replace '__QEMU_EXIT__', $qemuExitAddress `
    -replace '__ACPI_STATE_ADDR__', ('0x' + $acpiStateAddress) `
    -replace '__TIMER_STATE_ADDR__', ('0x' + $timerStateAddress) `
    -replace '__INTERRUPT_STATE_ADDR__', ('0x' + $interruptStateAddress) `
    -replace '__INTERRUPT_MASK_IGNORED_COUNT_ADDR__', ('0x' + $maskedInterruptIgnoredCountAddress) `
    -replace '__INTERRUPT_LAST_MASKED_VECTOR_ADDR__', ('0x' + $lastMaskedInterruptVectorAddress) `
    -replace '__ACPI_MAGIC_OFFSET__', $acpiMagicOffset `
    -replace '__ACPI_API_VERSION_OFFSET__', $acpiApiVersionOffset `
    -replace '__ACPI_PRESENT_OFFSET__', $acpiPresentOffset `
    -replace '__ACPI_REVISION_OFFSET__', $acpiRevisionOffset `
    -replace '__ACPI_TABLE_COUNT_OFFSET__', $acpiTableCountOffset `
    -replace '__ACPI_LAPIC_COUNT_OFFSET__', $acpiLapicCountOffset `
    -replace '__ACPI_IOAPIC_COUNT_OFFSET__', $acpiIoApicCountOffset `
    -replace '__ACPI_SCI_INTERRUPT_OFFSET__', $acpiSciInterruptOffset `
    -replace '__ACPI_PM_TIMER_BLOCK_OFFSET__', $acpiPmTimerBlockOffset `
    -replace '__ACPI_FLAGS_OFFSET__', $acpiFlagsOffset `
    -replace '__ACPI_RSDP_ADDR_OFFSET__', $acpiRsdpAddrOffset `
    -replace '__TIMER_ENABLED_OFFSET__', $timerEnabledOffset `
    -replace '__TIMER_PENDING_WAKE_COUNT_OFFSET__', $timerPendingWakeCountOffset `
    -replace '__TIMER_DISPATCH_COUNT_OFFSET__', $timerDispatchCountOffset `
    -replace '__TIMER_LAST_INTERRUPT_COUNT_OFFSET__', $timerLastInterruptCountOffset `
    -replace '__TIMER_TICK_QUANTUM_OFFSET__', $timerTickQuantumOffset `
    -replace '__INTERRUPT_DESCRIPTOR_READY_OFFSET__', $interruptDescriptorReadyOffset `
    -replace '__INTERRUPT_DESCRIPTOR_LOADED_OFFSET__', $interruptDescriptorLoadedOffset `
    -replace '__INTERRUPT_LAST_VECTOR_OFFSET__', $interruptLastVectorOffset `
    -replace '__INTERRUPT_COUNT_OFFSET__', $interruptCountOffset `
    -replace '__INTERRUPT_HISTORY_LEN_OFFSET__', $interruptHistoryLenOffset
$gdbScriptContent | Set-Content -Path $gdbScript -Encoding Ascii

$qemuProcess = $null
$gdbTimedOut = $false
try {
    $qemuArgs = @(
        "-M", "q35,accel=tcg",
        "-m", "128M",
        "-kernel", $artifact,
        "-display", "none",
        "-serial", "none",
        "-monitor", "none",
        "-vga", "none",
        "-device", "virtio-gpu-pci,edid=on,max_outputs=1,xres=1280,yres=800",
        "-no-reboot",
        "-no-shutdown",
        "-S",
        "-gdb", "tcp::$GdbPort",
        "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04"
    )
    $qemuProcess = Start-Process -FilePath $qemu -ArgumentList $qemuArgs -PassThru -RedirectStandardOutput $qemuStdout -RedirectStandardError $qemuStderr -WindowStyle Hidden
    Start-Sleep -Milliseconds 600

    $gdbProcess = Start-Process -FilePath $gdb -ArgumentList @("-q", "-x", $gdbScript) -PassThru -RedirectStandardOutput $gdbStdout -RedirectStandardError $gdbStderr -WindowStyle Hidden
    if (-not $gdbProcess.WaitForExit($TimeoutSeconds * 1000)) {
        $gdbTimedOut = $true
        try { $gdbProcess.Kill() } catch {}
    }

    if ($gdbTimedOut) { throw "gdb timed out after $TimeoutSeconds seconds" }
    $gdbExitCode = if ($null -eq $gdbProcess.ExitCode) { 0 } else { $gdbProcess.ExitCode }
    if ($gdbExitCode -ne 0) {
        $stderrTail = if (Test-Path $gdbStderr) { (Get-Content $gdbStderr -Tail 120) -join "`n" } else { "" }
        throw "gdb exited with code $gdbExitCode`n$stderrTail"
    }
} finally {
    if ($qemuProcess -and -not $qemuProcess.HasExited) {
        try { $qemuProcess.Kill() } catch {}
        try { $qemuProcess.WaitForExit(2000) | Out-Null } catch {}
    }
}

$out = Get-Content -Path $gdbStdout -Raw
$exitCodeStack = Extract-IntValue -Text $out -Name 'QEMU_EXIT_CODE_STACK'
$exitCodeEax = Extract-IntValue -Text $out -Name 'QEMU_EXIT_CODE_EAX'
$exitCodeEcx = Extract-IntValue -Text $out -Name 'QEMU_EXIT_CODE_ECX'
$acpiMagicValue = Extract-IntValue -Text $out -Name 'ACPI_MAGIC'
$acpiApiVersionValue = Extract-IntValue -Text $out -Name 'ACPI_API_VERSION'
$acpiPresentValue = Extract-IntValue -Text $out -Name 'ACPI_PRESENT'
$acpiRevisionValue = Extract-IntValue -Text $out -Name 'ACPI_REVISION'
$acpiTableCountValue = Extract-IntValue -Text $out -Name 'ACPI_TABLE_COUNT'
$acpiLapicCountValue = Extract-IntValue -Text $out -Name 'ACPI_LAPIC_COUNT'
$acpiIoApicCountValue = Extract-IntValue -Text $out -Name 'ACPI_IOAPIC_COUNT'
$acpiSciInterruptValue = Extract-IntValue -Text $out -Name 'ACPI_SCI_INTERRUPT'
$acpiPmTimerBlockValue = Extract-IntValue -Text $out -Name 'ACPI_PM_TIMER_BLOCK'
$acpiFlagsValue = Extract-IntValue -Text $out -Name 'ACPI_FLAGS'
$acpiRsdpAddrValue = Extract-IntValue -Text $out -Name 'ACPI_RSDP_ADDR'
$timerEnabledValue = Extract-IntValue -Text $out -Name 'TIMER_ENABLED'
$timerPendingWakeCountValue = Extract-IntValue -Text $out -Name 'TIMER_PENDING_WAKE_COUNT'
$timerDispatchCountValue = Extract-IntValue -Text $out -Name 'TIMER_DISPATCH_COUNT'
$timerLastInterruptCountValue = Extract-IntValue -Text $out -Name 'TIMER_LAST_INTERRUPT_COUNT'
$timerTickQuantumValue = Extract-IntValue -Text $out -Name 'TIMER_TICK_QUANTUM'
$interruptDescriptorReadyValue = Extract-IntValue -Text $out -Name 'INTERRUPT_DESCRIPTOR_READY'
$interruptDescriptorLoadedValue = Extract-IntValue -Text $out -Name 'INTERRUPT_DESCRIPTOR_LOADED'
$interruptLastVectorValue = Extract-IntValue -Text $out -Name 'INTERRUPT_LAST_VECTOR'
$interruptCountValue = Extract-IntValue -Text $out -Name 'INTERRUPT_COUNT'
$interruptHistoryLenValue = Extract-IntValue -Text $out -Name 'INTERRUPT_HISTORY_LEN'
$interruptMaskIgnoredCountValue = Extract-IntValue -Text $out -Name 'INTERRUPT_MASK_IGNORED_COUNT'
$interruptLastMaskedVectorValue = Extract-IntValue -Text $out -Name 'INTERRUPT_LAST_MASKED_VECTOR'

Write-Output "BAREMETAL_I386_QEMU_AVAILABLE=True"
Write-Output "BAREMETAL_I386_GDB_AVAILABLE=True"
Write-Output "BAREMETAL_I386_NM_AVAILABLE=True"
Write-Output "BAREMETAL_I386_QEMU_BINARY=$qemu"
Write-Output "BAREMETAL_I386_GDB_BINARY=$gdb"
Write-Output "BAREMETAL_I386_NM_BINARY=$nm"
Write-Output "BAREMETAL_I386_QEMU_ARTIFACT=$artifact"
Write-Output "BAREMETAL_I386_PLATFORM_PROBE_EXIT_CODE_STACK=$exitCodeStack"
Write-Output "BAREMETAL_I386_PLATFORM_PROBE_EXIT_CODE_EAX=$exitCodeEax"
Write-Output "BAREMETAL_I386_PLATFORM_PROBE_EXIT_CODE_ECX=$exitCodeEcx"
Write-Output "BAREMETAL_I386_PLATFORM_PROBE_ACPI_PRESENT=$acpiPresentValue"
Write-Output "BAREMETAL_I386_PLATFORM_PROBE_ACPI_TABLE_COUNT=$acpiTableCountValue"
Write-Output "BAREMETAL_I386_PLATFORM_PROBE_ACPI_LAPIC_COUNT=$acpiLapicCountValue"
Write-Output "BAREMETAL_I386_PLATFORM_PROBE_ACPI_IOAPIC_COUNT=$acpiIoApicCountValue"
Write-Output "BAREMETAL_I386_PLATFORM_PROBE_ACPI_SCI_INTERRUPT=$acpiSciInterruptValue"
Write-Output "BAREMETAL_I386_PLATFORM_PROBE_TIMER_DISPATCH_COUNT=$timerDispatchCountValue"
Write-Output "BAREMETAL_I386_PLATFORM_PROBE_TIMER_PENDING_WAKE_COUNT=$timerPendingWakeCountValue"
Write-Output "BAREMETAL_I386_PLATFORM_PROBE_INTERRUPT_MASK_IGNORED_COUNT=$interruptMaskIgnoredCountValue"
Write-Output "BAREMETAL_I386_PLATFORM_PROBE_INTERRUPT_LAST_MASKED_VECTOR=$interruptLastMaskedVectorValue"

$pass = (
    $acpiMagicValue -eq $acpiMagic -and
    $acpiApiVersionValue -eq $apiVersion -and
    $acpiPresentValue -eq 1 -and
    $acpiRevisionValue -ge 1 -and
    $acpiTableCountValue -ge 2 -and
    $acpiLapicCountValue -ge 1 -and
    $acpiIoApicCountValue -ge 1 -and
    $acpiSciInterruptValue -gt 0 -and
    $acpiPmTimerBlockValue -gt 0 -and
    $acpiFlagsValue -ne 0 -and
    $acpiRsdpAddrValue -gt 0 -and
    $timerEnabledValue -eq 1 -and
    $timerPendingWakeCountValue -eq 1 -and
    $timerDispatchCountValue -eq 0 -and
    $timerLastInterruptCountValue -eq 0 -and
    $timerTickQuantumValue -eq 1 -and
    $interruptDescriptorReadyValue -eq 1 -and
    $interruptDescriptorLoadedValue -eq 1 -and
    $interruptLastVectorValue -eq 0 -and
    $interruptCountValue -eq 0 -and
    $interruptHistoryLenValue -eq 1 -and
    $interruptMaskIgnoredCountValue -eq 1 -and
    $interruptLastMaskedVectorValue -eq $expectedMaskedVector
)

Write-Output "BAREMETAL_I386_PLATFORM_PROBE_PASS=$pass"
if (-not $pass) {
    throw "i386 platform probe validation failed.`n$out"
}
