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
$stateInterfaceOffset = 17
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
$outputModeWidthOffset = 0
$outputModeHeightOffset = 2
$outputModeRefreshHzOffset = 4
$outputModeStride = 6
$outputModeRowStride = 96

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

if ($null -eq $qemu -or $null -eq $gdb) {
    Write-Output "BAREMETAL_I386_QEMU_AVAILABLE=$([bool]($null -ne $qemu))"
    Write-Output "BAREMETAL_I386_GDB_AVAILABLE=$([bool]($null -ne $gdb))"
    Write-Output "BAREMETAL_I386_QEMU_VIRTIO_GPU_DISPLAY_PROBE=skipped"
    return
}
if ($null -eq $nm) {
    Write-Output "BAREMETAL_I386_QEMU_AVAILABLE=True"
    Write-Output "BAREMETAL_I386_QEMU_BINARY=$qemu"
    Write-Output "BAREMETAL_I386_GDB_BINARY=$gdb"
    Write-Output "BAREMETAL_I386_NM_AVAILABLE=False"
    Write-Output "BAREMETAL_I386_QEMU_VIRTIO_GPU_DISPLAY_PROBE=skipped"
    return
}

if ($GdbPort -le 0) { $GdbPort = Resolve-FreeTcpPort }

$gdbScript = Join-Path $releaseDir "qemu-i386-virtio-gpu-display-probe-$runStamp.gdb"
$gdbStdout = Join-Path $releaseDir "qemu-i386-virtio-gpu-display-probe-$runStamp.gdb.stdout.log"
$gdbStderr = Join-Path $releaseDir "qemu-i386-virtio-gpu-display-probe-$runStamp.gdb.stderr.log"
$qemuStdout = Join-Path $releaseDir "qemu-i386-virtio-gpu-display-probe-$runStamp.qemu.stdout.log"
$qemuStderr = Join-Path $releaseDir "qemu-i386-virtio-gpu-display-probe-$runStamp.qemu.stderr.log"

if (-not $SkipBuild) {
    & $zig build baremetal-i386 -Doptimize=Debug -Dbaremetal-virtio-gpu-display-probe=true --summary all
    if ($LASTEXITCODE -ne 0) { throw "zig build baremetal-i386 virtio-gpu display probe failed with exit code $LASTEXITCODE" }
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
if ($null -eq $artifact) { throw 'i386 virtio-gpu display artifact not found after build.' }

$symbolOutput = & $nm $artifact
if ($LASTEXITCODE -ne 0 -or $null -eq $symbolOutput -or $symbolOutput.Count -eq 0) {
    throw "Failed to resolve symbol table from $artifact using $nm"
}

$qemuExitAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[tT]\sbaremetal_main\.qemuExit$' -SymbolName "baremetal_main.qemuExit"
$displayStateAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[dDbB]\sbaremetal\.display_output\.state$' -SymbolName "baremetal.display_output.state"
$edidBytesAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[dDbB]\sbaremetal\.display_output\.edid_bytes$' -SymbolName "baremetal.display_output.edid_bytes"
$outputEntryCountAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[dDbB]\soc_display_output_entry_count_data$' -SymbolName "oc_display_output_entry_count_data"
$outputEntriesAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[dDbB]\soc_display_output_entries_data$' -SymbolName "oc_display_output_entries_data"
$outputInterfaceTypeAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[tT]\soc_display_output_interface_type$' -SymbolName "oc_display_output_interface_type"
$outputModeCountAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[dDbB]\soc_display_output_mode_count_data$' -SymbolName "oc_display_output_mode_count_data"
$outputModesAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[dDbB]\soc_display_output_modes_data$' -SymbolName "oc_display_output_modes_data"
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
  printf "DISPLAY_INTERFACE=%u\n", *(unsigned char*)(__DISPLAY_STATE_ADDR__ + __INTERFACE_OFFSET__)
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
  printf "DISPLAY_OUTPUT0_INTERFACE=%u\n", (unsigned int)(((unsigned char(*)(unsigned short))__OUTPUT_INTERFACE_TYPE_ADDR__)((unsigned short)0))
  printf "DISPLAY_OUTPUT0_EDID_PRESENT=%u\n", *(unsigned char*)(__OUTPUT_ENTRIES_ADDR__ + __OUTPUT_ENTRY_EDID_PRESENT_OFFSET__)
  printf "DISPLAY_OUTPUT0_CURRENT_WIDTH=%u\n", *(unsigned short*)(__OUTPUT_ENTRIES_ADDR__ + __OUTPUT_ENTRY_CURRENT_WIDTH_OFFSET__)
  printf "DISPLAY_OUTPUT0_CURRENT_HEIGHT=%u\n", *(unsigned short*)(__OUTPUT_ENTRIES_ADDR__ + __OUTPUT_ENTRY_CURRENT_HEIGHT_OFFSET__)
  printf "DISPLAY_OUTPUT0_PREFERRED_WIDTH=%u\n", *(unsigned short*)(__OUTPUT_ENTRIES_ADDR__ + __OUTPUT_ENTRY_PREFERRED_WIDTH_OFFSET__)
  printf "DISPLAY_OUTPUT0_PREFERRED_HEIGHT=%u\n", *(unsigned short*)(__OUTPUT_ENTRIES_ADDR__ + __OUTPUT_ENTRY_PREFERRED_HEIGHT_OFFSET__)
  printf "DISPLAY_OUTPUT0_CAPABILITY_FLAGS=%u\n", *(unsigned short*)(__OUTPUT_ENTRIES_ADDR__ + __OUTPUT_ENTRY_CAPABILITY_FLAGS_OFFSET__)
  printf "DISPLAY_OUTPUT0_MODE_COUNT=%u\n", *(unsigned short*)(__OUTPUT_MODE_COUNT_ADDR__)
  printf "DISPLAY_OUTPUT0_MODE0_WIDTH=%u\n", *(unsigned short*)(__OUTPUT_MODES_ADDR__ + __OUTPUT_MODE_WIDTH_OFFSET__)
  printf "DISPLAY_OUTPUT0_MODE0_HEIGHT=%u\n", *(unsigned short*)(__OUTPUT_MODES_ADDR__ + __OUTPUT_MODE_HEIGHT_OFFSET__)
  printf "DISPLAY_OUTPUT0_MODE0_REFRESH_HZ=%u\n", *(unsigned short*)(__OUTPUT_MODES_ADDR__ + __OUTPUT_MODE_REFRESH_OFFSET__)
  printf "DISPLAY_OUTPUT0_MODE1_WIDTH=%u\n", *(unsigned short*)(__OUTPUT_MODES_ADDR__ + __OUTPUT_MODE_STRIDE__ + __OUTPUT_MODE_WIDTH_OFFSET__)
  printf "DISPLAY_OUTPUT0_MODE1_HEIGHT=%u\n", *(unsigned short*)(__OUTPUT_MODES_ADDR__ + __OUTPUT_MODE_STRIDE__ + __OUTPUT_MODE_HEIGHT_OFFSET__)
  printf "DISPLAY_OUTPUT0_MODE1_REFRESH_HZ=%u\n", *(unsigned short*)(__OUTPUT_MODES_ADDR__ + __OUTPUT_MODE_STRIDE__ + __OUTPUT_MODE_REFRESH_OFFSET__)
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
    -replace '__OUTPUT_INTERFACE_TYPE_ADDR__', ('0x' + $outputInterfaceTypeAddress) `
    -replace '__OUTPUT_MODE_COUNT_ADDR__', ('0x' + $outputModeCountAddress) `
    -replace '__OUTPUT_MODES_ADDR__', ('0x' + $outputModesAddress) `
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
    -replace '__INTERFACE_OFFSET__', $stateInterfaceOffset `
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
    -replace '__OUTPUT_ENTRY_CAPABILITY_FLAGS_OFFSET__', $outputEntryCapabilityFlagsOffset `
    -replace '__OUTPUT_MODE_WIDTH_OFFSET__', $outputModeWidthOffset `
    -replace '__OUTPUT_MODE_HEIGHT_OFFSET__', $outputModeHeightOffset `
    -replace '__OUTPUT_MODE_REFRESH_OFFSET__', $outputModeRefreshHzOffset `
    -replace '__OUTPUT_MODE_STRIDE__', $outputModeStride `
    -replace '__OUTPUT_MODE_ROW_STRIDE__', $outputModeRowStride
$gdbScriptContent | Set-Content -Path $gdbScript -Encoding Ascii

$qemuProcess = $null
$gdbTimedOut = $false
try {
    $qemuArgs = @(
        "-M", "q35,accel=tcg"
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
$displayInterface = Extract-IntValue -Text $out -Name 'DISPLAY_INTERFACE'
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
$output0Interface = Extract-IntValue -Text $out -Name 'DISPLAY_OUTPUT0_INTERFACE'
$output0EdidPresent = Extract-IntValue -Text $out -Name 'DISPLAY_OUTPUT0_EDID_PRESENT'
$output0CurrentWidth = Extract-IntValue -Text $out -Name 'DISPLAY_OUTPUT0_CURRENT_WIDTH'
$output0CurrentHeight = Extract-IntValue -Text $out -Name 'DISPLAY_OUTPUT0_CURRENT_HEIGHT'
$output0PreferredWidth = Extract-IntValue -Text $out -Name 'DISPLAY_OUTPUT0_PREFERRED_WIDTH'
$output0PreferredHeight = Extract-IntValue -Text $out -Name 'DISPLAY_OUTPUT0_PREFERRED_HEIGHT'
$output0CapabilityFlags = Extract-IntValue -Text $out -Name 'DISPLAY_OUTPUT0_CAPABILITY_FLAGS'
$output0ModeCount = Extract-IntValue -Text $out -Name 'DISPLAY_OUTPUT0_MODE_COUNT'
$output0Mode0Width = Extract-IntValue -Text $out -Name 'DISPLAY_OUTPUT0_MODE0_WIDTH'
$output0Mode0Height = Extract-IntValue -Text $out -Name 'DISPLAY_OUTPUT0_MODE0_HEIGHT'
$output0Mode0RefreshHz = Extract-IntValue -Text $out -Name 'DISPLAY_OUTPUT0_MODE0_REFRESH_HZ'
$output0Mode1Width = Extract-IntValue -Text $out -Name 'DISPLAY_OUTPUT0_MODE1_WIDTH'
$output0Mode1Height = Extract-IntValue -Text $out -Name 'DISPLAY_OUTPUT0_MODE1_HEIGHT'
$output0Mode1RefreshHz = Extract-IntValue -Text $out -Name 'DISPLAY_OUTPUT0_MODE1_REFRESH_HZ'
$edid0 = Extract-IntValue -Text $out -Name 'DISPLAY_EDID_0'
$edid1 = Extract-IntValue -Text $out -Name 'DISPLAY_EDID_1'
$edid2 = Extract-IntValue -Text $out -Name 'DISPLAY_EDID_2'
$edid3 = Extract-IntValue -Text $out -Name 'DISPLAY_EDID_3'
$edid4 = Extract-IntValue -Text $out -Name 'DISPLAY_EDID_4'
$edid5 = Extract-IntValue -Text $out -Name 'DISPLAY_EDID_5'
$edid6 = Extract-IntValue -Text $out -Name 'DISPLAY_EDID_6'
$edid7 = Extract-IntValue -Text $out -Name 'DISPLAY_EDID_7'

Write-Output "BAREMETAL_I386_QEMU_AVAILABLE=True"
Write-Output "BAREMETAL_I386_QEMU_BINARY=$qemu"
Write-Output "BAREMETAL_I386_GDB_BINARY=$gdb"
Write-Output "BAREMETAL_I386_NM_BINARY=$nm"
Write-Output "BAREMETAL_I386_QEMU_ARTIFACT=$artifact"
Write-Output "BAREMETAL_I386_QEMU_VIRTIO_GPU_DISPLAY_PROBE_EXIT_CODE_STACK=$exitCodeStack"
Write-Output "BAREMETAL_I386_QEMU_VIRTIO_GPU_DISPLAY_PROBE_EXIT_CODE_EAX=$exitCodeEax"
Write-Output "BAREMETAL_I386_QEMU_VIRTIO_GPU_DISPLAY_PROBE_EXIT_CODE_ECX=$exitCodeEcx"
Write-Output "BAREMETAL_I386_QEMU_VIRTIO_GPU_DISPLAY_PROBE_MAGIC=$magic"
Write-Output "BAREMETAL_I386_QEMU_VIRTIO_GPU_DISPLAY_PROBE_API_VERSION=$version"
Write-Output "BAREMETAL_I386_QEMU_VIRTIO_GPU_DISPLAY_PROBE_BACKEND=$backend"
Write-Output "BAREMETAL_I386_QEMU_VIRTIO_GPU_DISPLAY_PROBE_CONTROLLER=$controller"
Write-Output "BAREMETAL_I386_QEMU_VIRTIO_GPU_DISPLAY_PROBE_CONNECTOR=$connector"
Write-Output "BAREMETAL_I386_QEMU_VIRTIO_GPU_DISPLAY_PROBE_HARDWARE_BACKED=$hardwareBacked"
Write-Output "BAREMETAL_I386_QEMU_VIRTIO_GPU_DISPLAY_PROBE_CONNECTED=$connected"
Write-Output "BAREMETAL_I386_QEMU_VIRTIO_GPU_DISPLAY_PROBE_EDID_PRESENT=$edidPresent"
Write-Output "BAREMETAL_I386_QEMU_VIRTIO_GPU_DISPLAY_PROBE_SCANOUT_COUNT=$scanoutCount"
Write-Output "BAREMETAL_I386_QEMU_VIRTIO_GPU_DISPLAY_PROBE_ACTIVE_SCANOUT=$activeScanout"
Write-Output "BAREMETAL_I386_QEMU_VIRTIO_GPU_DISPLAY_PROBE_PCI_BUS=$pciBus"
Write-Output "BAREMETAL_I386_QEMU_VIRTIO_GPU_DISPLAY_PROBE_PCI_DEVICE=$pciDevice"
Write-Output "BAREMETAL_I386_QEMU_VIRTIO_GPU_DISPLAY_PROBE_PCI_FUNCTION=$pciFunction"
Write-Output "BAREMETAL_I386_QEMU_VIRTIO_GPU_DISPLAY_PROBE_INTERFACE=$displayInterface"
Write-Output "BAREMETAL_I386_QEMU_VIRTIO_GPU_DISPLAY_PROBE_VENDOR_ID=$vendorId"
Write-Output "BAREMETAL_I386_QEMU_VIRTIO_GPU_DISPLAY_PROBE_DEVICE_ID=$deviceId"
Write-Output "BAREMETAL_I386_QEMU_VIRTIO_GPU_DISPLAY_PROBE_CURRENT_WIDTH=$currentWidth"
Write-Output "BAREMETAL_I386_QEMU_VIRTIO_GPU_DISPLAY_PROBE_CURRENT_HEIGHT=$currentHeight"
Write-Output "BAREMETAL_I386_QEMU_VIRTIO_GPU_DISPLAY_PROBE_PREFERRED_WIDTH=$preferredWidth"
Write-Output "BAREMETAL_I386_QEMU_VIRTIO_GPU_DISPLAY_PROBE_PREFERRED_HEIGHT=$preferredHeight"
Write-Output "BAREMETAL_I386_QEMU_VIRTIO_GPU_DISPLAY_PROBE_PHYSICAL_WIDTH=$physicalWidth"
Write-Output "BAREMETAL_I386_QEMU_VIRTIO_GPU_DISPLAY_PROBE_PHYSICAL_HEIGHT=$physicalHeight"
Write-Output "BAREMETAL_I386_QEMU_VIRTIO_GPU_DISPLAY_PROBE_MANUFACTURER_ID=$manufacturerId"
Write-Output "BAREMETAL_I386_QEMU_VIRTIO_GPU_DISPLAY_PROBE_PRODUCT_CODE=$productCode"
Write-Output "BAREMETAL_I386_QEMU_VIRTIO_GPU_DISPLAY_PROBE_SERIAL_NUMBER=$serialNumber"
Write-Output "BAREMETAL_I386_QEMU_VIRTIO_GPU_DISPLAY_PROBE_EDID_LENGTH=$edidLength"
Write-Output "BAREMETAL_I386_QEMU_VIRTIO_GPU_DISPLAY_PROBE_OUTPUT_ENTRY_COUNT=$outputEntryCount"
Write-Output "BAREMETAL_I386_QEMU_VIRTIO_GPU_DISPLAY_PROBE_OUTPUT0_CONNECTED=$output0Connected"
Write-Output "BAREMETAL_I386_QEMU_VIRTIO_GPU_DISPLAY_PROBE_OUTPUT0_SCANOUT=$output0Scanout"
Write-Output "BAREMETAL_I386_QEMU_VIRTIO_GPU_DISPLAY_PROBE_OUTPUT0_CONNECTOR=$output0Connector"
Write-Output "BAREMETAL_I386_QEMU_VIRTIO_GPU_DISPLAY_PROBE_OUTPUT0_INTERFACE=$output0Interface"
Write-Output "BAREMETAL_I386_QEMU_VIRTIO_GPU_DISPLAY_PROBE_OUTPUT0_EDID_PRESENT=$output0EdidPresent"
Write-Output "BAREMETAL_I386_QEMU_VIRTIO_GPU_DISPLAY_PROBE_OUTPUT0_CURRENT_WIDTH=$output0CurrentWidth"
Write-Output "BAREMETAL_I386_QEMU_VIRTIO_GPU_DISPLAY_PROBE_OUTPUT0_CURRENT_HEIGHT=$output0CurrentHeight"
Write-Output "BAREMETAL_I386_QEMU_VIRTIO_GPU_DISPLAY_PROBE_OUTPUT0_PREFERRED_WIDTH=$output0PreferredWidth"
Write-Output "BAREMETAL_I386_QEMU_VIRTIO_GPU_DISPLAY_PROBE_OUTPUT0_PREFERRED_HEIGHT=$output0PreferredHeight"
Write-Output "BAREMETAL_I386_QEMU_VIRTIO_GPU_DISPLAY_PROBE_OUTPUT0_CAPABILITY_FLAGS=$output0CapabilityFlags"
Write-Output "BAREMETAL_I386_QEMU_VIRTIO_GPU_DISPLAY_PROBE_OUTPUT0_MODE_COUNT=$output0ModeCount"
Write-Output "BAREMETAL_I386_QEMU_VIRTIO_GPU_DISPLAY_PROBE_OUTPUT0_MODE0_WIDTH=$output0Mode0Width"
Write-Output "BAREMETAL_I386_QEMU_VIRTIO_GPU_DISPLAY_PROBE_OUTPUT0_MODE0_HEIGHT=$output0Mode0Height"
Write-Output "BAREMETAL_I386_QEMU_VIRTIO_GPU_DISPLAY_PROBE_OUTPUT0_MODE0_REFRESH_HZ=$output0Mode0RefreshHz"
Write-Output "BAREMETAL_I386_QEMU_VIRTIO_GPU_DISPLAY_PROBE_OUTPUT0_MODE1_WIDTH=$output0Mode1Width"
Write-Output "BAREMETAL_I386_QEMU_VIRTIO_GPU_DISPLAY_PROBE_OUTPUT0_MODE1_HEIGHT=$output0Mode1Height"
Write-Output "BAREMETAL_I386_QEMU_VIRTIO_GPU_DISPLAY_PROBE_OUTPUT0_MODE1_REFRESH_HZ=$output0Mode1RefreshHz"

$pass = (
    $magic -eq $displayMagic -and
    $version -eq $apiVersion -and
    $backend -eq $expectedBackend -and
    $controller -eq $expectedController -and
    $connector -ge 1 -and
    $hardwareBacked -eq 1 -and
    $connected -eq 1 -and
    $edidPresent -eq 1 -and
    $scanoutCount -ge 1 -and
    $activeScanout -eq 0 -and
    $pciBus -ge 0 -and
    $pciDevice -ge 0 -and
    $pciFunction -eq 0 -and
    $displayInterface -ne 0 -and
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
    $output0Connector -eq $connector -and
    $output0Interface -eq $displayInterface -and
    $output0EdidPresent -eq 1 -and
    $output0CurrentWidth -eq $expectedWidth -and
    $output0CurrentHeight -eq $expectedHeight -and
    $output0PreferredWidth -gt 0 -and
    $output0PreferredHeight -gt 0 -and
    $output0CapabilityFlags -eq $capabilityFlags -and
    $output0ModeCount -ge 2 -and
    $output0Mode0Width -eq $preferredWidth -and
    $output0Mode0Height -eq $preferredHeight -and
    $output0Mode1Width -gt 0 -and
    $output0Mode1Height -gt 0 -and
    ($output0Mode1Width -ne $output0Mode0Width -or $output0Mode1Height -ne $output0Mode0Height) -and
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
    Write-Output "BAREMETAL_I386_QEMU_VIRTIO_GPU_DISPLAY_PROBE=pass"
    exit 0
}

Write-Output "BAREMETAL_I386_QEMU_VIRTIO_GPU_DISPLAY_PROBE=fail"
if (Test-Path $gdbStdout) { Get-Content -Path $gdbStdout -Tail 160 }
if (Test-Path $gdbStderr) { Get-Content -Path $gdbStderr -Tail 160 }
if (Test-Path $qemuStdout) { Get-Content -Path $qemuStdout -Tail 80 }
if (Test-Path $qemuStderr) { Get-Content -Path $qemuStderr -Tail 80 }
exit 1
