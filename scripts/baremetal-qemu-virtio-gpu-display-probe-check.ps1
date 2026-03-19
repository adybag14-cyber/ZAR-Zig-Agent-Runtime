# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 30,
    [int] $GdbPort = 0
)

$ErrorActionPreference = "Stop"

$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$releaseDir = Join-Path $repo "release"
$runStamp = [DateTime]::UtcNow.ToString("yyyyMMddHHmmssfff")

$displayMagic = 0x4f43444f
$apiVersion = 2
$expectedExitCode = 0x41
$expectedBackend = 2
$expectedController = 2
$expectedConnector = 1
$expectedVendorId = 0x1AF4
$expectedDeviceId = 0x1050
$expectedWidth = 1280
$expectedHeight = 800
$expectedMinEdidLength = 128
$expectedCapabilityDigital = 0x0001
$expectedCapabilityPreferredTiming = 0x0002
$expectedOutputEntryCount = 1

$stateMagicOffset = 0
$stateApiVersionOffset = 4
$stateBackendOffset = 6
$stateControllerOffset = 7
$stateConnectorOffset = 8
$stateHardwareBackedOffset = 9
$stateConnectedOffset = 10
$stateEdidPresentOffset = 11
$stateScanoutCountOffset = 12
$stateActiveScanoutOffset = 13
$statePciBusOffset = 14
$statePciDeviceOffset = 15
$statePciFunctionOffset = 16
$stateVendorIdOffset = 18
$stateDeviceIdOffset = 20
$stateCurrentWidthOffset = 22
$stateCurrentHeightOffset = 24
$statePreferredWidthOffset = 26
$statePreferredHeightOffset = 28
$statePhysicalWidthOffset = 30
$statePhysicalHeightOffset = 32
$stateManufacturerIdOffset = 34
$stateProductCodeOffset = 36
$stateSerialNumberOffset = 40
$stateEdidLengthOffset = 44
$stateCapabilityFlagsOffset = 46

$outputEntryConnectedOffset = 0
$outputEntryScanoutIndexOffset = 1
$outputEntryConnectorOffset = 2
$outputEntryEdidPresentOffset = 3
$outputEntryCurrentWidthOffset = 4
$outputEntryCurrentHeightOffset = 6
$outputEntryPreferredWidthOffset = 8
$outputEntryPreferredHeightOffset = 10
$outputEntryCapabilityFlagsOffset = 20

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

function Resolve-QemuExecutable { return Resolve-PreferredExecutable @("qemu-system-x86_64", "qemu-system-x86_64.exe", "C:\Program Files\qemu\qemu-system-x86_64.exe") }
function Resolve-GdbExecutable { return Resolve-PreferredExecutable @("gdb", "gdb.exe") }
function Resolve-NmExecutable { return Resolve-PreferredExecutable @("llvm-nm", "llvm-nm.exe", "nm", "nm.exe", "C:\Users\Ady\Documents\starpro\tooling\emsdk\upstream\bin\llvm-nm.exe") }
function Resolve-ClangExecutable { return Resolve-PreferredExecutable @("clang", "clang.exe", "C:\Users\Ady\Documents\starpro\tooling\emsdk\upstream\bin\clang.exe") }
function Resolve-LldExecutable { return Resolve-PreferredExecutable @("lld", "lld.exe", "C:\Users\Ady\Documents\starpro\tooling\emsdk\upstream\bin\lld.exe") }

function Resolve-ZigGlobalCacheDir {
    $candidates = @()
    if ($env:ZIG_GLOBAL_CACHE_DIR) { $candidates += $env:ZIG_GLOBAL_CACHE_DIR }
    if ($env:LOCALAPPDATA) { $candidates += (Join-Path $env:LOCALAPPDATA "zig") }
    if ($env:XDG_CACHE_HOME) { $candidates += (Join-Path $env:XDG_CACHE_HOME "zig") }
    if ($env:HOME) { $candidates += (Join-Path $env:HOME ".cache/zig") }
    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate)) { return $candidate }
    }
    return (Join-Path $repo ".zig-global-cache")
}

function Resolve-CompilerRtArchive {
    $cacheRoot = Resolve-ZigGlobalCacheDir
    $objRoot = Join-Path $cacheRoot "o"
    if (-not (Test-Path $objRoot)) { return $null }
    $candidate = Get-ChildItem -Path $objRoot -Recurse -Filter "libcompiler_rt.a" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($candidate) { return $candidate.FullName }
    return $null
}

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
$clang = Resolve-ClangExecutable
$lld = Resolve-LldExecutable
$compilerRt = Resolve-CompilerRtArchive
$zigGlobalCacheDir = Resolve-ZigGlobalCacheDir
$zigLocalCacheDir = if ($env:ZIG_LOCAL_CACHE_DIR -and $env:ZIG_LOCAL_CACHE_DIR.Trim().Length -gt 0) { $env:ZIG_LOCAL_CACHE_DIR } else { Join-Path $repo ".zig-cache" }

if ($null -eq $qemu -or $null -eq $gdb) {
    Write-Output "BAREMETAL_QEMU_AVAILABLE=$([bool]($null -ne $qemu))"
    Write-Output "BAREMETAL_GDB_AVAILABLE=$([bool]($null -ne $gdb))"
    Write-Output "BAREMETAL_QEMU_VIRTIO_GPU_DISPLAY_PROBE=skipped"
    return
}
if ($null -eq $nm) {
    Write-Output "BAREMETAL_QEMU_AVAILABLE=True"
    Write-Output "BAREMETAL_QEMU_BINARY=$qemu"
    Write-Output "BAREMETAL_GDB_BINARY=$gdb"
    Write-Output "BAREMETAL_NM_AVAILABLE=False"
    Write-Output "BAREMETAL_QEMU_VIRTIO_GPU_DISPLAY_PROBE=skipped"
    return
}
if ($null -eq $clang -or $null -eq $lld -or $null -eq $compilerRt) {
    Write-Output "BAREMETAL_QEMU_AVAILABLE=True"
    Write-Output "BAREMETAL_QEMU_BINARY=$qemu"
    Write-Output "BAREMETAL_GDB_BINARY=$gdb"
    Write-Output "BAREMETAL_NM_BINARY=$nm"
    Write-Output "BAREMETAL_QEMU_PVH_TOOLCHAIN_AVAILABLE=False"
    if ($null -eq $clang) { Write-Output "BAREMETAL_QEMU_PVH_MISSING=clang" }
    if ($null -eq $lld) { Write-Output "BAREMETAL_QEMU_PVH_MISSING=lld" }
    if ($null -eq $compilerRt) { Write-Output "BAREMETAL_QEMU_PVH_MISSING=libcompiler_rt.a" }
    Write-Output "BAREMETAL_QEMU_VIRTIO_GPU_DISPLAY_PROBE=skipped"
    return
}

if ($GdbPort -le 0) { $GdbPort = Resolve-FreeTcpPort }

$optionsPath = Join-Path $releaseDir "qemu-virtio-gpu-display-probe-options.zig"
$mainObj = Join-Path $releaseDir "openclaw-zig-baremetal-main-virtio-gpu-display-probe.o"
$bootObj = Join-Path $releaseDir "openclaw-zig-pvh-boot-virtio-gpu-display-probe.o"
$artifact = Join-Path $releaseDir "openclaw-zig-baremetal-pvh-virtio-gpu-display-probe.elf"
$bootSource = Join-Path $repo "scripts\baremetal\pvh_boot.S"
$linkerScript = Join-Path $repo "scripts\baremetal\pvh_lld.ld"
$gdbScript = Join-Path $releaseDir "qemu-virtio-gpu-display-probe-$runStamp.gdb"
$gdbStdout = Join-Path $releaseDir "qemu-virtio-gpu-display-probe-$runStamp.gdb.stdout.log"
$gdbStderr = Join-Path $releaseDir "qemu-virtio-gpu-display-probe-$runStamp.gdb.stderr.log"
$qemuStdout = Join-Path $releaseDir "qemu-virtio-gpu-display-probe-$runStamp.qemu.stdout.log"
$qemuStderr = Join-Path $releaseDir "qemu-virtio-gpu-display-probe-$runStamp.qemu.stderr.log"

if (-not $SkipBuild) {
    New-Item -ItemType Directory -Force -Path $zigGlobalCacheDir | Out-Null
    New-Item -ItemType Directory -Force -Path $zigLocalCacheDir | Out-Null
@"
pub const qemu_smoke: bool = false;
pub const console_probe_banner: bool = false;
pub const framebuffer_probe_banner: bool = false;
pub const framebuffer_probe_width: u16 = 0;
pub const framebuffer_probe_height: u16 = 0;
pub const ata_storage_probe: bool = false;
pub const ata_gpt_installer_probe: bool = false;
pub const virtio_gpu_display_probe: bool = true;
pub const rtl8139_probe: bool = false;
pub const rtl8139_arp_probe: bool = false;
pub const rtl8139_ipv4_probe: bool = false;
pub const rtl8139_udp_probe: bool = false;
pub const rtl8139_tcp_probe: bool = false;
pub const rtl8139_dhcp_probe: bool = false;
pub const rtl8139_dns_probe: bool = false;
pub const rtl8139_http_post_probe: bool = false;
pub const tool_exec_probe: bool = false;
pub const rtl8139_gateway_probe: bool = false;
"@ | Set-Content -Path $optionsPath -Encoding Ascii

    & $zig build-obj -fno-strip -fsingle-threaded -ODebug -target x86_64-freestanding-none -mcpu baseline --dep build_options "-Mroot=$repo\src\baremetal_main.zig" "-Mbuild_options=$optionsPath" --cache-dir "$zigLocalCacheDir" --global-cache-dir "$zigGlobalCacheDir" --name "openclaw-zig-baremetal-main-virtio-gpu-display-probe" "-femit-bin=$mainObj"
    if ($LASTEXITCODE -ne 0) { throw "zig build-obj for virtio-gpu display probe runtime failed with exit code $LASTEXITCODE" }

    & $clang -c -target x86_64-unknown-elf $bootSource -o $bootObj
    if ($LASTEXITCODE -ne 0) { throw "clang assemble for virtio-gpu display probe PVH shim failed with exit code $LASTEXITCODE" }

    & $lld -flavor gnu -m elf_x86_64 -o $artifact -T $linkerScript $mainObj $bootObj $compilerRt
    if ($LASTEXITCODE -ne 0) { throw "lld link for virtio-gpu display probe PVH artifact failed with exit code $LASTEXITCODE" }
}

$symbolOutput = & $nm $artifact
if ($LASTEXITCODE -ne 0 -or $null -eq $symbolOutput -or $symbolOutput.Count -eq 0) {
    throw "Failed to resolve symbol table from $artifact using $nm"
}

$qemuExitAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[tT]\sbaremetal_main\.qemuExit$' -SymbolName "baremetal_main.qemuExit"
$displayStateAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[dDbB]\sbaremetal\.display_output\.state$' -SymbolName "baremetal.display_output.state"
$edidBytesAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[dDbB]\sbaremetal\.display_output\.edid_bytes$' -SymbolName "baremetal.display_output.edid_bytes"
$outputEntryCountAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[dDbB]\soc_display_output_entry_count_data$' -SymbolName "oc_display_output_entry_count_data"
$outputEntriesAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[dDbB]\soc_display_output_entries_data$' -SymbolName "oc_display_output_entries_data"
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
  printf "QEMU_EXIT_CODE_RDI=%u\n", (unsigned int)($rdi & 0xff)
  printf "QEMU_EXIT_CODE_RCX=%u\n", (unsigned int)($rcx & 0xff)
  printf "QEMU_EXIT_CODE_RSI=%u\n", (unsigned int)($rsi & 0xff)
  printf "DISPLAY_MAGIC=%u\n", *(unsigned int*)(__DISPLAY_STATE_ADDR__ + __MAGIC_OFFSET__)
  printf "DISPLAY_API_VERSION=%u\n", *(unsigned short*)(__DISPLAY_STATE_ADDR__ + __API_VERSION_OFFSET__)
  printf "DISPLAY_BACKEND=%u\n", *(unsigned char*)(__DISPLAY_STATE_ADDR__ + __BACKEND_OFFSET__)
  printf "DISPLAY_CONTROLLER=%u\n", *(unsigned char*)(__DISPLAY_STATE_ADDR__ + __CONTROLLER_OFFSET__)
  printf "DISPLAY_CONNECTOR=%u\n", *(unsigned char*)(__DISPLAY_STATE_ADDR__ + __CONNECTOR_OFFSET__)
  printf "DISPLAY_HARDWARE_BACKED=%u\n", *(unsigned char*)(__DISPLAY_STATE_ADDR__ + __HARDWARE_BACKED_OFFSET__)
  printf "DISPLAY_CONNECTED=%u\n", *(unsigned char*)(__DISPLAY_STATE_ADDR__ + __CONNECTED_OFFSET__)
  printf "DISPLAY_EDID_PRESENT=%u\n", *(unsigned char*)(__DISPLAY_STATE_ADDR__ + __EDID_PRESENT_OFFSET__)
  printf "DISPLAY_SCANOUT_COUNT=%u\n", *(unsigned char*)(__DISPLAY_STATE_ADDR__ + __SCANOUT_COUNT_OFFSET__)
  printf "DISPLAY_ACTIVE_SCANOUT=%u\n", *(unsigned char*)(__DISPLAY_STATE_ADDR__ + __ACTIVE_SCANOUT_OFFSET__)
  printf "DISPLAY_PCI_BUS=%u\n", *(unsigned char*)(__DISPLAY_STATE_ADDR__ + __PCI_BUS_OFFSET__)
  printf "DISPLAY_PCI_DEVICE=%u\n", *(unsigned char*)(__DISPLAY_STATE_ADDR__ + __PCI_DEVICE_OFFSET__)
  printf "DISPLAY_PCI_FUNCTION=%u\n", *(unsigned char*)(__DISPLAY_STATE_ADDR__ + __PCI_FUNCTION_OFFSET__)
  printf "DISPLAY_VENDOR_ID=%u\n", *(unsigned short*)(__DISPLAY_STATE_ADDR__ + __VENDOR_ID_OFFSET__)
  printf "DISPLAY_DEVICE_ID=%u\n", *(unsigned short*)(__DISPLAY_STATE_ADDR__ + __DEVICE_ID_OFFSET__)
  printf "DISPLAY_CURRENT_WIDTH=%u\n", *(unsigned short*)(__DISPLAY_STATE_ADDR__ + __CURRENT_WIDTH_OFFSET__)
  printf "DISPLAY_CURRENT_HEIGHT=%u\n", *(unsigned short*)(__DISPLAY_STATE_ADDR__ + __CURRENT_HEIGHT_OFFSET__)
  printf "DISPLAY_PREFERRED_WIDTH=%u\n", *(unsigned short*)(__DISPLAY_STATE_ADDR__ + __PREFERRED_WIDTH_OFFSET__)
  printf "DISPLAY_PREFERRED_HEIGHT=%u\n", *(unsigned short*)(__DISPLAY_STATE_ADDR__ + __PREFERRED_HEIGHT_OFFSET__)
  printf "DISPLAY_PHYSICAL_WIDTH=%u\n", *(unsigned short*)(__DISPLAY_STATE_ADDR__ + __PHYSICAL_WIDTH_OFFSET__)
  printf "DISPLAY_PHYSICAL_HEIGHT=%u\n", *(unsigned short*)(__DISPLAY_STATE_ADDR__ + __PHYSICAL_HEIGHT_OFFSET__)
  printf "DISPLAY_MANUFACTURER_ID=%u\n", *(unsigned short*)(__DISPLAY_STATE_ADDR__ + __MANUFACTURER_ID_OFFSET__)
  printf "DISPLAY_PRODUCT_CODE=%u\n", *(unsigned short*)(__DISPLAY_STATE_ADDR__ + __PRODUCT_CODE_OFFSET__)
  printf "DISPLAY_SERIAL_NUMBER=%u\n", *(unsigned int*)(__DISPLAY_STATE_ADDR__ + __SERIAL_NUMBER_OFFSET__)
  printf "DISPLAY_EDID_LENGTH=%u\n", *(unsigned short*)(__DISPLAY_STATE_ADDR__ + __EDID_LENGTH_OFFSET__)
  printf "DISPLAY_CAPABILITY_FLAGS=%u\n", *(unsigned short*)(__DISPLAY_STATE_ADDR__ + __CAPABILITY_FLAGS_OFFSET__)
  printf "DISPLAY_OUTPUT_ENTRY_COUNT=%u\n", *(unsigned short*)(__OUTPUT_ENTRY_COUNT_ADDR__)
  printf "DISPLAY_OUTPUT0_CONNECTED=%u\n", *(unsigned char*)(__OUTPUT_ENTRIES_ADDR__ + __OUTPUT_ENTRY_CONNECTED_OFFSET__)
  printf "DISPLAY_OUTPUT0_SCANOUT=%u\n", *(unsigned char*)(__OUTPUT_ENTRIES_ADDR__ + __OUTPUT_ENTRY_SCANOUT_OFFSET__)
  printf "DISPLAY_OUTPUT0_CONNECTOR=%u\n", *(unsigned char*)(__OUTPUT_ENTRIES_ADDR__ + __OUTPUT_ENTRY_CONNECTOR_OFFSET__)
  printf "DISPLAY_OUTPUT0_EDID_PRESENT=%u\n", *(unsigned char*)(__OUTPUT_ENTRIES_ADDR__ + __OUTPUT_ENTRY_EDID_PRESENT_OFFSET__)
  printf "DISPLAY_OUTPUT0_CURRENT_WIDTH=%u\n", *(unsigned short*)(__OUTPUT_ENTRIES_ADDR__ + __OUTPUT_ENTRY_CURRENT_WIDTH_OFFSET__)
  printf "DISPLAY_OUTPUT0_CURRENT_HEIGHT=%u\n", *(unsigned short*)(__OUTPUT_ENTRIES_ADDR__ + __OUTPUT_ENTRY_CURRENT_HEIGHT_OFFSET__)
  printf "DISPLAY_OUTPUT0_PREFERRED_WIDTH=%u\n", *(unsigned short*)(__OUTPUT_ENTRIES_ADDR__ + __OUTPUT_ENTRY_PREFERRED_WIDTH_OFFSET__)
  printf "DISPLAY_OUTPUT0_PREFERRED_HEIGHT=%u\n", *(unsigned short*)(__OUTPUT_ENTRIES_ADDR__ + __OUTPUT_ENTRY_PREFERRED_HEIGHT_OFFSET__)
  printf "DISPLAY_OUTPUT0_CAPABILITY_FLAGS=%u\n", *(unsigned short*)(__OUTPUT_ENTRIES_ADDR__ + __OUTPUT_ENTRY_CAPABILITY_FLAGS_OFFSET__)
  printf "DISPLAY_EDID_0=%u\n", *(unsigned char*)(__EDID_BYTES_ADDR__ + 0)
  printf "DISPLAY_EDID_1=%u\n", *(unsigned char*)(__EDID_BYTES_ADDR__ + 1)
  printf "DISPLAY_EDID_2=%u\n", *(unsigned char*)(__EDID_BYTES_ADDR__ + 2)
  printf "DISPLAY_EDID_3=%u\n", *(unsigned char*)(__EDID_BYTES_ADDR__ + 3)
  printf "DISPLAY_EDID_4=%u\n", *(unsigned char*)(__EDID_BYTES_ADDR__ + 4)
  printf "DISPLAY_EDID_5=%u\n", *(unsigned char*)(__EDID_BYTES_ADDR__ + 5)
  printf "DISPLAY_EDID_6=%u\n", *(unsigned char*)(__EDID_BYTES_ADDR__ + 6)
  printf "DISPLAY_EDID_7=%u\n", *(unsigned char*)(__EDID_BYTES_ADDR__ + 7)
  quit
end
continue
'@

$gdbScriptContent = $gdbTemplate `
    -replace '__ARTIFACT__', $artifactForGdb `
    -replace '__GDBPORT__', $GdbPort `
    -replace '__QEMU_EXIT__', $qemuExitAddress `
    -replace '__DISPLAY_STATE_ADDR__', ('0x' + $displayStateAddress) `
    -replace '__EDID_BYTES_ADDR__', ('0x' + $edidBytesAddress) `
    -replace '__OUTPUT_ENTRY_COUNT_ADDR__', ('0x' + $outputEntryCountAddress) `
    -replace '__OUTPUT_ENTRIES_ADDR__', ('0x' + $outputEntriesAddress) `
    -replace '__MAGIC_OFFSET__', $stateMagicOffset `
    -replace '__API_VERSION_OFFSET__', $stateApiVersionOffset `
    -replace '__BACKEND_OFFSET__', $stateBackendOffset `
    -replace '__CONTROLLER_OFFSET__', $stateControllerOffset `
    -replace '__CONNECTOR_OFFSET__', $stateConnectorOffset `
    -replace '__HARDWARE_BACKED_OFFSET__', $stateHardwareBackedOffset `
    -replace '__CONNECTED_OFFSET__', $stateConnectedOffset `
    -replace '__EDID_PRESENT_OFFSET__', $stateEdidPresentOffset `
    -replace '__SCANOUT_COUNT_OFFSET__', $stateScanoutCountOffset `
    -replace '__ACTIVE_SCANOUT_OFFSET__', $stateActiveScanoutOffset `
    -replace '__PCI_BUS_OFFSET__', $statePciBusOffset `
    -replace '__PCI_DEVICE_OFFSET__', $statePciDeviceOffset `
    -replace '__PCI_FUNCTION_OFFSET__', $statePciFunctionOffset `
    -replace '__VENDOR_ID_OFFSET__', $stateVendorIdOffset `
    -replace '__DEVICE_ID_OFFSET__', $stateDeviceIdOffset `
    -replace '__CURRENT_WIDTH_OFFSET__', $stateCurrentWidthOffset `
    -replace '__CURRENT_HEIGHT_OFFSET__', $stateCurrentHeightOffset `
    -replace '__PREFERRED_WIDTH_OFFSET__', $statePreferredWidthOffset `
    -replace '__PREFERRED_HEIGHT_OFFSET__', $statePreferredHeightOffset `
    -replace '__PHYSICAL_WIDTH_OFFSET__', $statePhysicalWidthOffset `
    -replace '__PHYSICAL_HEIGHT_OFFSET__', $statePhysicalHeightOffset `
    -replace '__MANUFACTURER_ID_OFFSET__', $stateManufacturerIdOffset `
    -replace '__PRODUCT_CODE_OFFSET__', $stateProductCodeOffset `
    -replace '__SERIAL_NUMBER_OFFSET__', $stateSerialNumberOffset `
    -replace '__EDID_LENGTH_OFFSET__', $stateEdidLengthOffset `
    -replace '__CAPABILITY_FLAGS_OFFSET__', $stateCapabilityFlagsOffset `
    -replace '__OUTPUT_ENTRY_CONNECTED_OFFSET__', $outputEntryConnectedOffset `
    -replace '__OUTPUT_ENTRY_SCANOUT_OFFSET__', $outputEntryScanoutIndexOffset `
    -replace '__OUTPUT_ENTRY_CONNECTOR_OFFSET__', $outputEntryConnectorOffset `
    -replace '__OUTPUT_ENTRY_EDID_PRESENT_OFFSET__', $outputEntryEdidPresentOffset `
    -replace '__OUTPUT_ENTRY_CURRENT_WIDTH_OFFSET__', $outputEntryCurrentWidthOffset `
    -replace '__OUTPUT_ENTRY_CURRENT_HEIGHT_OFFSET__', $outputEntryCurrentHeightOffset `
    -replace '__OUTPUT_ENTRY_PREFERRED_WIDTH_OFFSET__', $outputEntryPreferredWidthOffset `
    -replace '__OUTPUT_ENTRY_PREFERRED_HEIGHT_OFFSET__', $outputEntryPreferredHeightOffset `
    -replace '__OUTPUT_ENTRY_CAPABILITY_FLAGS_OFFSET__', $outputEntryCapabilityFlagsOffset
$gdbScriptContent | Set-Content -Path $gdbScript -Encoding Ascii

$qemuProcess = $null
$gdbTimedOut = $false
try {
    $qemuArgs = @(
        "-M", "q35,accel=tcg"
        "-cpu", "qemu64"
        "-m", "128M"
        "-kernel", $artifact
        "-display", "none"
        "-serial", "none"
        "-monitor", "none"
        "-vga", "none"
        "-device", "virtio-gpu-pci,edid=on,max_outputs=1,xres=1280,yres=800"
        "-no-reboot"
        "-no-shutdown"
        "-S"
        "-gdb", "tcp::$GdbPort"
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
$exitCodeRdi = Extract-IntValue -Text $out -Name 'QEMU_EXIT_CODE_RDI'
$exitCodeRcx = Extract-IntValue -Text $out -Name 'QEMU_EXIT_CODE_RCX'
$exitCodeRsi = Extract-IntValue -Text $out -Name 'QEMU_EXIT_CODE_RSI'
$magic = Extract-IntValue -Text $out -Name 'DISPLAY_MAGIC'
$version = Extract-IntValue -Text $out -Name 'DISPLAY_API_VERSION'
$backend = Extract-IntValue -Text $out -Name 'DISPLAY_BACKEND'
$controller = Extract-IntValue -Text $out -Name 'DISPLAY_CONTROLLER'
$connector = Extract-IntValue -Text $out -Name 'DISPLAY_CONNECTOR'
$hardwareBacked = Extract-IntValue -Text $out -Name 'DISPLAY_HARDWARE_BACKED'
$connected = Extract-IntValue -Text $out -Name 'DISPLAY_CONNECTED'
$edidPresent = Extract-IntValue -Text $out -Name 'DISPLAY_EDID_PRESENT'
$scanoutCount = Extract-IntValue -Text $out -Name 'DISPLAY_SCANOUT_COUNT'
$activeScanout = Extract-IntValue -Text $out -Name 'DISPLAY_ACTIVE_SCANOUT'
$pciBus = Extract-IntValue -Text $out -Name 'DISPLAY_PCI_BUS'
$pciDevice = Extract-IntValue -Text $out -Name 'DISPLAY_PCI_DEVICE'
$pciFunction = Extract-IntValue -Text $out -Name 'DISPLAY_PCI_FUNCTION'
$vendorId = Extract-IntValue -Text $out -Name 'DISPLAY_VENDOR_ID'
$deviceId = Extract-IntValue -Text $out -Name 'DISPLAY_DEVICE_ID'
$currentWidth = Extract-IntValue -Text $out -Name 'DISPLAY_CURRENT_WIDTH'
$currentHeight = Extract-IntValue -Text $out -Name 'DISPLAY_CURRENT_HEIGHT'
$preferredWidth = Extract-IntValue -Text $out -Name 'DISPLAY_PREFERRED_WIDTH'
$preferredHeight = Extract-IntValue -Text $out -Name 'DISPLAY_PREFERRED_HEIGHT'
$physicalWidth = Extract-IntValue -Text $out -Name 'DISPLAY_PHYSICAL_WIDTH'
$physicalHeight = Extract-IntValue -Text $out -Name 'DISPLAY_PHYSICAL_HEIGHT'
$manufacturerId = Extract-IntValue -Text $out -Name 'DISPLAY_MANUFACTURER_ID'
$productCode = Extract-IntValue -Text $out -Name 'DISPLAY_PRODUCT_CODE'
$serialNumber = Extract-IntValue -Text $out -Name 'DISPLAY_SERIAL_NUMBER'
$edidLength = Extract-IntValue -Text $out -Name 'DISPLAY_EDID_LENGTH'
$capabilityFlags = Extract-IntValue -Text $out -Name 'DISPLAY_CAPABILITY_FLAGS'
$outputEntryCount = Extract-IntValue -Text $out -Name 'DISPLAY_OUTPUT_ENTRY_COUNT'
$output0Connected = Extract-IntValue -Text $out -Name 'DISPLAY_OUTPUT0_CONNECTED'
$output0Scanout = Extract-IntValue -Text $out -Name 'DISPLAY_OUTPUT0_SCANOUT'
$output0Connector = Extract-IntValue -Text $out -Name 'DISPLAY_OUTPUT0_CONNECTOR'
$output0EdidPresent = Extract-IntValue -Text $out -Name 'DISPLAY_OUTPUT0_EDID_PRESENT'
$output0CurrentWidth = Extract-IntValue -Text $out -Name 'DISPLAY_OUTPUT0_CURRENT_WIDTH'
$output0CurrentHeight = Extract-IntValue -Text $out -Name 'DISPLAY_OUTPUT0_CURRENT_HEIGHT'
$output0PreferredWidth = Extract-IntValue -Text $out -Name 'DISPLAY_OUTPUT0_PREFERRED_WIDTH'
$output0PreferredHeight = Extract-IntValue -Text $out -Name 'DISPLAY_OUTPUT0_PREFERRED_HEIGHT'
$output0CapabilityFlags = Extract-IntValue -Text $out -Name 'DISPLAY_OUTPUT0_CAPABILITY_FLAGS'
$edid0 = Extract-IntValue -Text $out -Name 'DISPLAY_EDID_0'
$edid1 = Extract-IntValue -Text $out -Name 'DISPLAY_EDID_1'
$edid2 = Extract-IntValue -Text $out -Name 'DISPLAY_EDID_2'
$edid3 = Extract-IntValue -Text $out -Name 'DISPLAY_EDID_3'
$edid4 = Extract-IntValue -Text $out -Name 'DISPLAY_EDID_4'
$edid5 = Extract-IntValue -Text $out -Name 'DISPLAY_EDID_5'
$edid6 = Extract-IntValue -Text $out -Name 'DISPLAY_EDID_6'
$edid7 = Extract-IntValue -Text $out -Name 'DISPLAY_EDID_7'

Write-Output "BAREMETAL_QEMU_AVAILABLE=True"
Write-Output "BAREMETAL_QEMU_BINARY=$qemu"
Write-Output "BAREMETAL_GDB_BINARY=$gdb"
Write-Output "BAREMETAL_NM_BINARY=$nm"
Write-Output "BAREMETAL_QEMU_PVH_CLANG=$clang"
Write-Output "BAREMETAL_QEMU_PVH_LLD=$lld"
Write-Output "BAREMETAL_QEMU_PVH_COMPILER_RT=$compilerRt"
Write-Output "BAREMETAL_QEMU_ARTIFACT=$artifact"
Write-Output "BAREMETAL_QEMU_VIRTIO_GPU_DISPLAY_PROBE_EXIT_CODE_RDI=$exitCodeRdi"
Write-Output "BAREMETAL_QEMU_VIRTIO_GPU_DISPLAY_PROBE_EXIT_CODE_RCX=$exitCodeRcx"
Write-Output "BAREMETAL_QEMU_VIRTIO_GPU_DISPLAY_PROBE_EXIT_CODE_RSI=$exitCodeRsi"
Write-Output "BAREMETAL_QEMU_VIRTIO_GPU_DISPLAY_PROBE_MAGIC=$magic"
Write-Output "BAREMETAL_QEMU_VIRTIO_GPU_DISPLAY_PROBE_API_VERSION=$version"
Write-Output "BAREMETAL_QEMU_VIRTIO_GPU_DISPLAY_PROBE_BACKEND=$backend"
Write-Output "BAREMETAL_QEMU_VIRTIO_GPU_DISPLAY_PROBE_CONTROLLER=$controller"
Write-Output "BAREMETAL_QEMU_VIRTIO_GPU_DISPLAY_PROBE_CONNECTOR=$connector"
Write-Output "BAREMETAL_QEMU_VIRTIO_GPU_DISPLAY_PROBE_HARDWARE_BACKED=$hardwareBacked"
Write-Output "BAREMETAL_QEMU_VIRTIO_GPU_DISPLAY_PROBE_CONNECTED=$connected"
Write-Output "BAREMETAL_QEMU_VIRTIO_GPU_DISPLAY_PROBE_EDID_PRESENT=$edidPresent"
Write-Output "BAREMETAL_QEMU_VIRTIO_GPU_DISPLAY_PROBE_SCANOUT_COUNT=$scanoutCount"
Write-Output "BAREMETAL_QEMU_VIRTIO_GPU_DISPLAY_PROBE_ACTIVE_SCANOUT=$activeScanout"
Write-Output "BAREMETAL_QEMU_VIRTIO_GPU_DISPLAY_PROBE_PCI_BUS=$pciBus"
Write-Output "BAREMETAL_QEMU_VIRTIO_GPU_DISPLAY_PROBE_PCI_DEVICE=$pciDevice"
Write-Output "BAREMETAL_QEMU_VIRTIO_GPU_DISPLAY_PROBE_PCI_FUNCTION=$pciFunction"
Write-Output "BAREMETAL_QEMU_VIRTIO_GPU_DISPLAY_PROBE_VENDOR_ID=$vendorId"
Write-Output "BAREMETAL_QEMU_VIRTIO_GPU_DISPLAY_PROBE_DEVICE_ID=$deviceId"
Write-Output "BAREMETAL_QEMU_VIRTIO_GPU_DISPLAY_PROBE_CURRENT_WIDTH=$currentWidth"
Write-Output "BAREMETAL_QEMU_VIRTIO_GPU_DISPLAY_PROBE_CURRENT_HEIGHT=$currentHeight"
Write-Output "BAREMETAL_QEMU_VIRTIO_GPU_DISPLAY_PROBE_PREFERRED_WIDTH=$preferredWidth"
Write-Output "BAREMETAL_QEMU_VIRTIO_GPU_DISPLAY_PROBE_PREFERRED_HEIGHT=$preferredHeight"
Write-Output "BAREMETAL_QEMU_VIRTIO_GPU_DISPLAY_PROBE_PHYSICAL_WIDTH=$physicalWidth"
Write-Output "BAREMETAL_QEMU_VIRTIO_GPU_DISPLAY_PROBE_PHYSICAL_HEIGHT=$physicalHeight"
Write-Output "BAREMETAL_QEMU_VIRTIO_GPU_DISPLAY_PROBE_MANUFACTURER_ID=$manufacturerId"
Write-Output "BAREMETAL_QEMU_VIRTIO_GPU_DISPLAY_PROBE_PRODUCT_CODE=$productCode"
Write-Output "BAREMETAL_QEMU_VIRTIO_GPU_DISPLAY_PROBE_SERIAL_NUMBER=$serialNumber"
Write-Output "BAREMETAL_QEMU_VIRTIO_GPU_DISPLAY_PROBE_EDID_LENGTH=$edidLength"
Write-Output "BAREMETAL_QEMU_VIRTIO_GPU_DISPLAY_PROBE_OUTPUT_ENTRY_COUNT=$outputEntryCount"
Write-Output "BAREMETAL_QEMU_VIRTIO_GPU_DISPLAY_PROBE_OUTPUT0_CONNECTED=$output0Connected"
Write-Output "BAREMETAL_QEMU_VIRTIO_GPU_DISPLAY_PROBE_OUTPUT0_SCANOUT=$output0Scanout"
Write-Output "BAREMETAL_QEMU_VIRTIO_GPU_DISPLAY_PROBE_OUTPUT0_CONNECTOR=$output0Connector"
Write-Output "BAREMETAL_QEMU_VIRTIO_GPU_DISPLAY_PROBE_OUTPUT0_EDID_PRESENT=$output0EdidPresent"
Write-Output "BAREMETAL_QEMU_VIRTIO_GPU_DISPLAY_PROBE_OUTPUT0_CURRENT_WIDTH=$output0CurrentWidth"
Write-Output "BAREMETAL_QEMU_VIRTIO_GPU_DISPLAY_PROBE_OUTPUT0_CURRENT_HEIGHT=$output0CurrentHeight"
Write-Output "BAREMETAL_QEMU_VIRTIO_GPU_DISPLAY_PROBE_OUTPUT0_PREFERRED_WIDTH=$output0PreferredWidth"
Write-Output "BAREMETAL_QEMU_VIRTIO_GPU_DISPLAY_PROBE_OUTPUT0_PREFERRED_HEIGHT=$output0PreferredHeight"
Write-Output "BAREMETAL_QEMU_VIRTIO_GPU_DISPLAY_PROBE_OUTPUT0_CAPABILITY_FLAGS=$output0CapabilityFlags"

$pass = (
    $magic -eq $displayMagic -and
    $version -eq $apiVersion -and
    $backend -eq $expectedBackend -and
    $controller -eq $expectedController -and
    $connector -eq $expectedConnector -and
    $hardwareBacked -eq 1 -and
    $connected -eq 1 -and
    $edidPresent -eq 1 -and
    $scanoutCount -ge 1 -and
    $activeScanout -eq 0 -and
    $pciBus -ge 0 -and
    $pciDevice -ge 0 -and
    $pciFunction -eq 0 -and
    $vendorId -eq $expectedVendorId -and
    $deviceId -eq $expectedDeviceId -and
    $currentWidth -eq $expectedWidth -and
    $currentHeight -eq $expectedHeight -and
    $preferredWidth -gt 0 -and
    $preferredHeight -gt 0 -and
    $physicalWidth -gt 0 -and
    $physicalHeight -gt 0 -and
    $manufacturerId -gt 0 -and
    $productCode -gt 0 -and
    $edidLength -ge $expectedMinEdidLength -and
    $outputEntryCount -eq $expectedOutputEntryCount -and
    $output0Connected -eq 1 -and
    $output0Scanout -eq 0 -and
    $output0Connector -eq $expectedConnector -and
    $output0EdidPresent -eq 1 -and
    $output0CurrentWidth -eq $expectedWidth -and
    $output0CurrentHeight -eq $expectedHeight -and
    $output0PreferredWidth -gt 0 -and
    $output0PreferredHeight -gt 0 -and
    $output0CapabilityFlags -eq $capabilityFlags -and
    ($capabilityFlags -band $expectedCapabilityDigital) -ne 0 -and
    ($capabilityFlags -band $expectedCapabilityPreferredTiming) -ne 0 -and
    $edid0 -eq 0 -and
    $edid1 -eq 255 -and
    $edid2 -eq 255 -and
    $edid3 -eq 255 -and
    $edid4 -eq 255 -and
    $edid5 -eq 255 -and
    $edid6 -eq 255 -and
    $edid7 -eq 0
)

if ($pass) {
    Write-Output "BAREMETAL_QEMU_VIRTIO_GPU_DISPLAY_PROBE=pass"
    exit 0
}

Write-Output "BAREMETAL_QEMU_VIRTIO_GPU_DISPLAY_PROBE=fail"
if (Test-Path $gdbStdout) { Get-Content -Path $gdbStdout -Tail 160 }
if (Test-Path $gdbStderr) { Get-Content -Path $gdbStderr -Tail 160 }
if (Test-Path $qemuStdout) { Get-Content -Path $qemuStdout -Tail 80 }
if (Test-Path $qemuStderr) { Get-Content -Path $qemuStderr -Tail 80 }
exit 1
