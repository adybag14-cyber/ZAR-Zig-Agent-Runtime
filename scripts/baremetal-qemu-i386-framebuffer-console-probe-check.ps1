# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 30,
    [int] $GdbPort = 0,
    [int] $ModeWidth = 640,
    [int] $ModeHeight = 400
)

$ErrorActionPreference = "Stop"

$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$releaseDir = Join-Path $repo "release"
$runStamp = [DateTime]::UtcNow.ToString("yyyyMMddHHmmssfff")

$framebufferMagic = 0x4f434642
$apiVersion = 2
$consoleBackendFramebuffer = 2
$expectedWidth = $ModeWidth
$expectedHeight = $ModeHeight
$expectedCols = [int]($ModeWidth / 8)
$expectedRows = [int]($ModeHeight / 16)
$expectedPitch = $ModeWidth * 4
$expectedFramebufferBytes = $ModeWidth * $ModeHeight * 4
$expectedBytesPerPixel = 4
$expectedCellWidth = 8
$expectedCellHeight = 16
$expectedFgColor = 0x00FFFFFF
$expectedBgColor = 0x00000000
$expectedDisplayVendorId = 0x1234
$expectedSupportedModeCount = 5

if ($ModeWidth -eq 640 -and $ModeHeight -eq 400) {
    $expectedModeIndex = 0
} elseif ($ModeWidth -eq 800 -and $ModeHeight -eq 600) {
    $expectedModeIndex = 1
} elseif ($ModeWidth -eq 1024 -and $ModeHeight -eq 768) {
    $expectedModeIndex = 2
} elseif ($ModeWidth -eq 1280 -and $ModeHeight -eq 720) {
    $expectedModeIndex = 3
} elseif ($ModeWidth -eq 1280 -and $ModeHeight -eq 1024) {
    $expectedModeIndex = 4
} else {
    throw "Unsupported framebuffer probe mode: ${ModeWidth}x${ModeHeight}"
}

if ($ModeWidth -ne 640 -or $ModeHeight -ne 400) {
    throw "i386 framebuffer probe currently supports only the default 640x400 mode."
}

$stateMagicOffset = 0
$stateApiVersionOffset = 4
$stateWidthOffset = 6
$stateHeightOffset = 8
$stateColsOffset = 10
$stateRowsOffset = 12
$statePitchOffset = 16
$stateFramebufferBytesOffset = 20
$stateFramebufferAddrOffset = 24
$stateBytesPerPixelOffset = 32
$stateBackendOffset = 33
$stateHardwareBackedOffset = 34
$stateWriteCountOffset = 36
$stateClearCountOffset = 40
$statePresentCountOffset = 44
$stateCellWidthOffset = 48
$stateCellHeightOffset = 49
$stateFgColorOffset = 52
$stateBgColorOffset = 56
$stateDisplayVendorOffset = 60
$stateDisplayDeviceOffset = 62
$stateDisplayPciBusOffset = 64
$stateDisplayPciDeviceOffset = 65
$stateDisplayPciFunctionOffset = 66
$stateSupportedModeCountOffset = 67
$stateCurrentModeIndexOffset = 68

$pixel0OffsetBytes = 0
$pixelOOffsetBytes = (((1 * $expectedWidth) + 3) * 4)
$pixelKOffsetBytes = (((1 * $expectedWidth) + 9) * 4)

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
$scriptStem = [System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
$buildPrefix = Join-Path $repo ("zig-out\" + $scriptStem)
$env:ZIG_LOCAL_CACHE_DIR = Join-Path $repo (".zig-cache-" + $scriptStem)
$env:ZIG_GLOBAL_CACHE_DIR = Join-Path $repo (".zig-global-cache-" + $scriptStem)
New-Item -ItemType Directory -Force -Path $buildPrefix | Out-Null

$zig = Resolve-ZigExecutable
$qemu = Resolve-QemuExecutable
$gdb = Resolve-GdbExecutable
$nm = Resolve-NmExecutable

if ($null -eq $qemu -or $null -eq $gdb) {
    Write-Output "BAREMETAL_I386_QEMU_AVAILABLE=$([bool]($null -ne $qemu))"
    Write-Output "BAREMETAL_I386_GDB_AVAILABLE=$([bool]($null -ne $gdb))"
    Write-Output "BAREMETAL_I386_QEMU_FRAMEBUFFER_CONSOLE_PROBE=skipped"
    return
}
if ($null -eq $nm) {
    Write-Output "BAREMETAL_I386_QEMU_AVAILABLE=True"
    Write-Output "BAREMETAL_I386_QEMU_BINARY=$qemu"
    Write-Output "BAREMETAL_I386_GDB_BINARY=$gdb"
    Write-Output "BAREMETAL_I386_NM_AVAILABLE=False"
    Write-Output "BAREMETAL_I386_QEMU_FRAMEBUFFER_CONSOLE_PROBE=skipped"
    return
}

if ($GdbPort -le 0) { $GdbPort = Resolve-FreeTcpPort }

$gdbScript = Join-Path $releaseDir "qemu-i386-framebuffer-console-probe-$runStamp.gdb"
$gdbStdout = Join-Path $releaseDir "qemu-i386-framebuffer-console-probe-$runStamp.gdb.stdout.log"
$gdbStderr = Join-Path $releaseDir "qemu-i386-framebuffer-console-probe-$runStamp.gdb.stderr.log"
$qemuStdout = Join-Path $releaseDir "qemu-i386-framebuffer-console-probe-$runStamp.qemu.stdout.log"
$qemuStderr = Join-Path $releaseDir "qemu-i386-framebuffer-console-probe-$runStamp.qemu.stderr.log"

if (-not $SkipBuild) {
    & $zig build baremetal-i386 -Doptimize=Debug -Dbaremetal-framebuffer-probe-banner=true --prefix $buildPrefix --summary all
    if ($LASTEXITCODE -ne 0) { throw "zig build baremetal-i386 framebuffer console probe failed with exit code $LASTEXITCODE" }
}

$artifact = Join-Path $buildPrefix 'bin\openclaw-zig-baremetal-i386.elf'
if (-not (Test-Path $artifact)) { throw "i386 framebuffer console artifact not found at expected path: $artifact" }
$artifact = (Resolve-Path $artifact).Path

$symbolOutput = & $nm $artifact
if ($LASTEXITCODE -ne 0 -or $null -eq $symbolOutput -or $symbolOutput.Count -eq 0) {
    throw "Failed to resolve symbol table from $artifact using $nm"
}

$startAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[Tt]\s_start$' -SymbolName "_start"
$spinPauseAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[tT]\sbaremetal_main\.spinPause$' -SymbolName "baremetal_main.spinPause"
$framebufferStateAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[dDbB]\sbaremetal\.framebuffer_console\.state$' -SymbolName "baremetal.framebuffer_console.state"
$artifactForGdb = $artifact.Replace('\', '/')

Remove-PathWithRetry $gdbStdout
Remove-PathWithRetry $gdbStderr
Remove-PathWithRetry $qemuStdout
Remove-PathWithRetry $qemuStderr

$gdbTemplate = @'
set pagination off
set confirm off
set remotecache off
set $stage = 0
file __ARTIFACT__
handle SIGQUIT nostop noprint pass
target remote :__GDBPORT__
break *0x__START__
commands
  silent
  printf "HIT_START=1\n"
  continue
end
break *0x__SPINPAUSE__
commands
  silent
  if $stage == 0
    set $stage = 1
    set $fb = *(unsigned long long*)(__FRAMEBUFFER_STATE_ADDR__ + __FRAMEBUFFER_ADDR_OFFSET__)
    printf "FRAMEBUFFER_STATE_ADDR=%llu\n", (unsigned long long)__FRAMEBUFFER_STATE_ADDR__
    printf "FRAMEBUFFER_MAGIC=%u\n", *(unsigned int*)(__FRAMEBUFFER_STATE_ADDR__ + __MAGIC_OFFSET__)
    printf "FRAMEBUFFER_API_VERSION=%u\n", *(unsigned short*)(__FRAMEBUFFER_STATE_ADDR__ + __API_VERSION_OFFSET__)
    printf "FRAMEBUFFER_WIDTH=%u\n", *(unsigned short*)(__FRAMEBUFFER_STATE_ADDR__ + __WIDTH_OFFSET__)
    printf "FRAMEBUFFER_HEIGHT=%u\n", *(unsigned short*)(__FRAMEBUFFER_STATE_ADDR__ + __HEIGHT_OFFSET__)
    printf "FRAMEBUFFER_COLS=%u\n", *(unsigned short*)(__FRAMEBUFFER_STATE_ADDR__ + __COLS_OFFSET__)
    printf "FRAMEBUFFER_ROWS=%u\n", *(unsigned short*)(__FRAMEBUFFER_STATE_ADDR__ + __ROWS_OFFSET__)
    printf "FRAMEBUFFER_PITCH=%u\n", *(unsigned int*)(__FRAMEBUFFER_STATE_ADDR__ + __PITCH_OFFSET__)
    printf "FRAMEBUFFER_BYTES=%u\n", *(unsigned int*)(__FRAMEBUFFER_STATE_ADDR__ + __FRAMEBUFFER_BYTES_OFFSET__)
    printf "FRAMEBUFFER_ADDR=%llu\n", $fb
    printf "FRAMEBUFFER_BPP=%u\n", *(unsigned char*)(__FRAMEBUFFER_STATE_ADDR__ + __BYTES_PER_PIXEL_OFFSET__)
    printf "FRAMEBUFFER_BACKEND=%u\n", *(unsigned char*)(__FRAMEBUFFER_STATE_ADDR__ + __BACKEND_OFFSET__)
    printf "FRAMEBUFFER_HARDWARE_BACKED=%u\n", *(unsigned char*)(__FRAMEBUFFER_STATE_ADDR__ + __HARDWARE_BACKED_OFFSET__)
    printf "FRAMEBUFFER_WRITE_COUNT=%u\n", *(unsigned int*)(__FRAMEBUFFER_STATE_ADDR__ + __WRITE_COUNT_OFFSET__)
    printf "FRAMEBUFFER_CLEAR_COUNT=%u\n", *(unsigned int*)(__FRAMEBUFFER_STATE_ADDR__ + __CLEAR_COUNT_OFFSET__)
    printf "FRAMEBUFFER_PRESENT_COUNT=%u\n", *(unsigned int*)(__FRAMEBUFFER_STATE_ADDR__ + __PRESENT_COUNT_OFFSET__)
    printf "FRAMEBUFFER_CELL_WIDTH=%u\n", *(unsigned char*)(__FRAMEBUFFER_STATE_ADDR__ + __CELL_WIDTH_OFFSET__)
    printf "FRAMEBUFFER_CELL_HEIGHT=%u\n", *(unsigned char*)(__FRAMEBUFFER_STATE_ADDR__ + __CELL_HEIGHT_OFFSET__)
    printf "FRAMEBUFFER_FG_COLOR=%u\n", *(unsigned int*)(__FRAMEBUFFER_STATE_ADDR__ + __FG_COLOR_OFFSET__)
    printf "FRAMEBUFFER_BG_COLOR=%u\n", *(unsigned int*)(__FRAMEBUFFER_STATE_ADDR__ + __BG_COLOR_OFFSET__)
    printf "FRAMEBUFFER_DISPLAY_VENDOR=%u\n", *(unsigned short*)(__FRAMEBUFFER_STATE_ADDR__ + __DISPLAY_VENDOR_OFFSET__)
    printf "FRAMEBUFFER_DISPLAY_DEVICE=%u\n", *(unsigned short*)(__FRAMEBUFFER_STATE_ADDR__ + __DISPLAY_DEVICE_OFFSET__)
    printf "FRAMEBUFFER_DISPLAY_PCI_BUS=%u\n", *(unsigned char*)(__FRAMEBUFFER_STATE_ADDR__ + __DISPLAY_PCI_BUS_OFFSET__)
    printf "FRAMEBUFFER_DISPLAY_PCI_DEVICE=%u\n", *(unsigned char*)(__FRAMEBUFFER_STATE_ADDR__ + __DISPLAY_PCI_DEVICE_OFFSET__)
    printf "FRAMEBUFFER_DISPLAY_PCI_FUNCTION=%u\n", *(unsigned char*)(__FRAMEBUFFER_STATE_ADDR__ + __DISPLAY_PCI_FUNCTION_OFFSET__)
    printf "FRAMEBUFFER_SUPPORTED_MODE_COUNT=%u\n", *(unsigned char*)(__FRAMEBUFFER_STATE_ADDR__ + __SUPPORTED_MODE_COUNT_OFFSET__)
    printf "FRAMEBUFFER_CURRENT_MODE_INDEX=%u\n", *(unsigned char*)(__FRAMEBUFFER_STATE_ADDR__ + __CURRENT_MODE_INDEX_OFFSET__)
    printf "FRAMEBUFFER_PIXEL0=%u\n", *(unsigned int*)($fb + __PIXEL0_OFFSET__)
    printf "FRAMEBUFFER_PIXEL_O=%u\n", *(unsigned int*)($fb + __PIXEL_O_OFFSET__)
    printf "FRAMEBUFFER_PIXEL_K=%u\n", *(unsigned int*)($fb + __PIXEL_K_OFFSET__)
    quit
  end
  continue
end
continue
'@

$gdbScriptContent = $gdbTemplate `
    -replace '__ARTIFACT__', $artifactForGdb `
    -replace '__GDBPORT__', $GdbPort `
    -replace '__START__', $startAddress `
    -replace '__SPINPAUSE__', $spinPauseAddress `
    -replace '__FRAMEBUFFER_STATE_ADDR__', ('0x' + $framebufferStateAddress) `
    -replace '__MAGIC_OFFSET__', $stateMagicOffset `
    -replace '__API_VERSION_OFFSET__', $stateApiVersionOffset `
    -replace '__WIDTH_OFFSET__', $stateWidthOffset `
    -replace '__HEIGHT_OFFSET__', $stateHeightOffset `
    -replace '__COLS_OFFSET__', $stateColsOffset `
    -replace '__ROWS_OFFSET__', $stateRowsOffset `
    -replace '__PITCH_OFFSET__', $statePitchOffset `
    -replace '__FRAMEBUFFER_BYTES_OFFSET__', $stateFramebufferBytesOffset `
    -replace '__FRAMEBUFFER_ADDR_OFFSET__', $stateFramebufferAddrOffset `
    -replace '__BYTES_PER_PIXEL_OFFSET__', $stateBytesPerPixelOffset `
    -replace '__BACKEND_OFFSET__', $stateBackendOffset `
    -replace '__HARDWARE_BACKED_OFFSET__', $stateHardwareBackedOffset `
    -replace '__WRITE_COUNT_OFFSET__', $stateWriteCountOffset `
    -replace '__CLEAR_COUNT_OFFSET__', $stateClearCountOffset `
    -replace '__PRESENT_COUNT_OFFSET__', $statePresentCountOffset `
    -replace '__CELL_WIDTH_OFFSET__', $stateCellWidthOffset `
    -replace '__CELL_HEIGHT_OFFSET__', $stateCellHeightOffset `
    -replace '__FG_COLOR_OFFSET__', $stateFgColorOffset `
    -replace '__BG_COLOR_OFFSET__', $stateBgColorOffset `
    -replace '__DISPLAY_VENDOR_OFFSET__', $stateDisplayVendorOffset `
    -replace '__DISPLAY_DEVICE_OFFSET__', $stateDisplayDeviceOffset `
    -replace '__DISPLAY_PCI_BUS_OFFSET__', $stateDisplayPciBusOffset `
    -replace '__DISPLAY_PCI_DEVICE_OFFSET__', $stateDisplayPciDeviceOffset `
    -replace '__DISPLAY_PCI_FUNCTION_OFFSET__', $stateDisplayPciFunctionOffset `
    -replace '__SUPPORTED_MODE_COUNT_OFFSET__', $stateSupportedModeCountOffset `
    -replace '__CURRENT_MODE_INDEX_OFFSET__', $stateCurrentModeIndexOffset `
    -replace '__PIXEL0_OFFSET__', $pixel0OffsetBytes `
    -replace '__PIXEL_O_OFFSET__', $pixelOOffsetBytes `
    -replace '__PIXEL_K_OFFSET__', $pixelKOffsetBytes
$gdbScriptContent | Set-Content -Path $gdbScript -Encoding Ascii

$qemuProcess = $null
$gdbTimedOut = $false
try {
    $qemuArgs = @(
        "-M", "pc,accel=tcg"
        "-m", "128M"
        "-kernel", $artifact
        "-display", "none"
        "-serial", "none"
        "-monitor", "none"
        "-vga", "std"
        "-no-reboot"
        "-no-shutdown"
        "-S"
        "-gdb", "tcp::$GdbPort"
        "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04"
    )
    $qemuProcess = Start-Process -FilePath $qemu -ArgumentList $qemuArgs -PassThru -RedirectStandardOutput $qemuStdout -RedirectStandardError $qemuStderr
    Start-Sleep -Milliseconds 600

    $gdbProcess = Start-Process -FilePath $gdb -ArgumentList @("-q", "-x", $gdbScript) -PassThru -RedirectStandardOutput $gdbStdout -RedirectStandardError $gdbStderr
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
$hitStart = Extract-IntValue -Text $out -Name 'HIT_START'
$magic = Extract-IntValue -Text $out -Name 'FRAMEBUFFER_MAGIC'
$version = Extract-IntValue -Text $out -Name 'FRAMEBUFFER_API_VERSION'
$width = Extract-IntValue -Text $out -Name 'FRAMEBUFFER_WIDTH'
$height = Extract-IntValue -Text $out -Name 'FRAMEBUFFER_HEIGHT'
$cols = Extract-IntValue -Text $out -Name 'FRAMEBUFFER_COLS'
$rows = Extract-IntValue -Text $out -Name 'FRAMEBUFFER_ROWS'
$pitch = Extract-IntValue -Text $out -Name 'FRAMEBUFFER_PITCH'
$framebufferBytes = Extract-IntValue -Text $out -Name 'FRAMEBUFFER_BYTES'
$framebufferAddr = Extract-IntValue -Text $out -Name 'FRAMEBUFFER_ADDR'
$bytesPerPixel = Extract-IntValue -Text $out -Name 'FRAMEBUFFER_BPP'
$backend = Extract-IntValue -Text $out -Name 'FRAMEBUFFER_BACKEND'
$hardwareBacked = Extract-IntValue -Text $out -Name 'FRAMEBUFFER_HARDWARE_BACKED'
$writeCount = Extract-IntValue -Text $out -Name 'FRAMEBUFFER_WRITE_COUNT'
$clearCount = Extract-IntValue -Text $out -Name 'FRAMEBUFFER_CLEAR_COUNT'
$presentCount = Extract-IntValue -Text $out -Name 'FRAMEBUFFER_PRESENT_COUNT'
$cellWidth = Extract-IntValue -Text $out -Name 'FRAMEBUFFER_CELL_WIDTH'
$cellHeight = Extract-IntValue -Text $out -Name 'FRAMEBUFFER_CELL_HEIGHT'
$fgColor = Extract-IntValue -Text $out -Name 'FRAMEBUFFER_FG_COLOR'
$bgColor = Extract-IntValue -Text $out -Name 'FRAMEBUFFER_BG_COLOR'
$displayVendor = Extract-IntValue -Text $out -Name 'FRAMEBUFFER_DISPLAY_VENDOR'
$displayDevice = Extract-IntValue -Text $out -Name 'FRAMEBUFFER_DISPLAY_DEVICE'
$displayPciBus = Extract-IntValue -Text $out -Name 'FRAMEBUFFER_DISPLAY_PCI_BUS'
$displayPciDevice = Extract-IntValue -Text $out -Name 'FRAMEBUFFER_DISPLAY_PCI_DEVICE'
$displayPciFunction = Extract-IntValue -Text $out -Name 'FRAMEBUFFER_DISPLAY_PCI_FUNCTION'
$supportedModeCount = Extract-IntValue -Text $out -Name 'FRAMEBUFFER_SUPPORTED_MODE_COUNT'
$currentModeIndex = Extract-IntValue -Text $out -Name 'FRAMEBUFFER_CURRENT_MODE_INDEX'
$pixel0 = Extract-IntValue -Text $out -Name 'FRAMEBUFFER_PIXEL0'
$pixelO = Extract-IntValue -Text $out -Name 'FRAMEBUFFER_PIXEL_O'
$pixelK = Extract-IntValue -Text $out -Name 'FRAMEBUFFER_PIXEL_K'

Write-Output "BAREMETAL_I386_QEMU_AVAILABLE=True"
Write-Output "BAREMETAL_I386_QEMU_BINARY=$qemu"
Write-Output "BAREMETAL_I386_GDB_BINARY=$gdb"
Write-Output "BAREMETAL_I386_NM_BINARY=$nm"
Write-Output "BAREMETAL_I386_QEMU_ARTIFACT=$artifact"
Write-Output "BAREMETAL_I386_QEMU_FRAMEBUFFER_CONSOLE_PROBE_HIT_START=$hitStart"
Write-Output "BAREMETAL_I386_QEMU_FRAMEBUFFER_CONSOLE_PROBE_MAGIC=$magic"
Write-Output "BAREMETAL_I386_QEMU_FRAMEBUFFER_CONSOLE_PROBE_API_VERSION=$version"
Write-Output "BAREMETAL_I386_QEMU_FRAMEBUFFER_CONSOLE_PROBE_WIDTH=$width"
Write-Output "BAREMETAL_I386_QEMU_FRAMEBUFFER_CONSOLE_PROBE_HEIGHT=$height"
Write-Output "BAREMETAL_I386_QEMU_FRAMEBUFFER_CONSOLE_PROBE_COLS=$cols"
Write-Output "BAREMETAL_I386_QEMU_FRAMEBUFFER_CONSOLE_PROBE_ROWS=$rows"
Write-Output "BAREMETAL_I386_QEMU_FRAMEBUFFER_CONSOLE_PROBE_PITCH=$pitch"
Write-Output "BAREMETAL_I386_QEMU_FRAMEBUFFER_CONSOLE_PROBE_FRAMEBUFFER_BYTES=$framebufferBytes"
Write-Output "BAREMETAL_I386_QEMU_FRAMEBUFFER_CONSOLE_PROBE_FRAMEBUFFER_ADDR=$framebufferAddr"
Write-Output "BAREMETAL_I386_QEMU_FRAMEBUFFER_CONSOLE_PROBE_BPP=$bytesPerPixel"
Write-Output "BAREMETAL_I386_QEMU_FRAMEBUFFER_CONSOLE_PROBE_BACKEND=$backend"
Write-Output "BAREMETAL_I386_QEMU_FRAMEBUFFER_CONSOLE_PROBE_HARDWARE_BACKED=$hardwareBacked"
Write-Output "BAREMETAL_I386_QEMU_FRAMEBUFFER_CONSOLE_PROBE_WRITE_COUNT=$writeCount"
Write-Output "BAREMETAL_I386_QEMU_FRAMEBUFFER_CONSOLE_PROBE_CLEAR_COUNT=$clearCount"
Write-Output "BAREMETAL_I386_QEMU_FRAMEBUFFER_CONSOLE_PROBE_PRESENT_COUNT=$presentCount"
Write-Output "BAREMETAL_I386_QEMU_FRAMEBUFFER_CONSOLE_PROBE_CELL_WIDTH=$cellWidth"
Write-Output "BAREMETAL_I386_QEMU_FRAMEBUFFER_CONSOLE_PROBE_CELL_HEIGHT=$cellHeight"
Write-Output "BAREMETAL_I386_QEMU_FRAMEBUFFER_CONSOLE_PROBE_FG_COLOR=$fgColor"
Write-Output "BAREMETAL_I386_QEMU_FRAMEBUFFER_CONSOLE_PROBE_BG_COLOR=$bgColor"
Write-Output "BAREMETAL_I386_QEMU_FRAMEBUFFER_CONSOLE_PROBE_DISPLAY_VENDOR=$displayVendor"
Write-Output "BAREMETAL_I386_QEMU_FRAMEBUFFER_CONSOLE_PROBE_DISPLAY_DEVICE=$displayDevice"
Write-Output "BAREMETAL_I386_QEMU_FRAMEBUFFER_CONSOLE_PROBE_DISPLAY_PCI_BUS=$displayPciBus"
Write-Output "BAREMETAL_I386_QEMU_FRAMEBUFFER_CONSOLE_PROBE_DISPLAY_PCI_DEVICE=$displayPciDevice"
Write-Output "BAREMETAL_I386_QEMU_FRAMEBUFFER_CONSOLE_PROBE_DISPLAY_PCI_FUNCTION=$displayPciFunction"
Write-Output "BAREMETAL_I386_QEMU_FRAMEBUFFER_CONSOLE_PROBE_SUPPORTED_MODE_COUNT=$supportedModeCount"
Write-Output "BAREMETAL_I386_QEMU_FRAMEBUFFER_CONSOLE_PROBE_CURRENT_MODE_INDEX=$currentModeIndex"
Write-Output "BAREMETAL_I386_QEMU_FRAMEBUFFER_CONSOLE_PROBE_PIXEL0=$pixel0"
Write-Output "BAREMETAL_I386_QEMU_FRAMEBUFFER_CONSOLE_PROBE_PIXEL_O=$pixelO"
Write-Output "BAREMETAL_I386_QEMU_FRAMEBUFFER_CONSOLE_PROBE_PIXEL_K=$pixelK"

$pass = (
    $hitStart -eq 1 -and
    $magic -eq $framebufferMagic -and
    $version -eq $apiVersion -and
    $width -eq $expectedWidth -and
    $height -eq $expectedHeight -and
    $cols -eq $expectedCols -and
    $rows -eq $expectedRows -and
    $pitch -eq $expectedPitch -and
    $framebufferBytes -eq $expectedFramebufferBytes -and
    $framebufferAddr -gt 0 -and
    (($framebufferAddr % 4096) -eq 0) -and
    $bytesPerPixel -eq $expectedBytesPerPixel -and
    $backend -eq $consoleBackendFramebuffer -and
    $hardwareBacked -eq 1 -and
    $writeCount -eq 2 -and
    $clearCount -eq 0 -and
    $presentCount -eq 2 -and
    $cellWidth -eq $expectedCellWidth -and
    $cellHeight -eq $expectedCellHeight -and
    $fgColor -eq $expectedFgColor -and
    $bgColor -eq $expectedBgColor -and
    $displayVendor -eq $expectedDisplayVendorId -and
    ($displayDevice -eq 0x1110 -or $displayDevice -eq 0x1111) -and
    $displayPciBus -ge 0 -and
    $displayPciDevice -ge 0 -and
    $displayPciFunction -eq 0 -and
    $supportedModeCount -eq $expectedSupportedModeCount -and
    $currentModeIndex -eq $expectedModeIndex -and
    $pixel0 -eq $expectedBgColor -and
    $pixelO -eq $expectedFgColor -and
    $pixelK -eq $expectedFgColor
)

if ($pass) {
    Write-Output "BAREMETAL_I386_QEMU_FRAMEBUFFER_CONSOLE_PROBE=pass"
    exit 0
}

Write-Output "BAREMETAL_I386_QEMU_FRAMEBUFFER_CONSOLE_PROBE=fail"
if (Test-Path $gdbStdout) { Get-Content -Path $gdbStdout -Tail 160 }
if (Test-Path $gdbStderr) { Get-Content -Path $gdbStderr -Tail 160 }
if (Test-Path $qemuStdout) { Get-Content -Path $qemuStdout -Tail 80 }
if (Test-Path $qemuStderr) { Get-Content -Path $qemuStderr -Tail 80 }
exit 1
