# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 30,
    [int] $DiskSizeMiB = 8
)

$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$releaseDir = Join-Path $repo 'release'
$expectedProbeCode = 0x5A
$expectedExitCode = ($expectedProbeCode * 2) + 1
$toolLayoutMagic = 0x4f43544c
$filesystemMagic = 0x4f434653
$filesystemSuperblockLba = 130
$blockSize = 512
$expectedLoaderMarker = 'backend=virtio_block'
$expectedBootMountRegistryMarker = '/runtime/mounts/boot.txt'
$expectedMountRegistryMarker = '/runtime/mounts/runtime.txt'
$expectedCacheMountRegistryMarker = '/runtime/mounts/cache.txt'
$expectedMountPayloadMarker = 'mounted-via-alias'

function Resolve-ZigExecutable {
    $defaultWindowsZig = 'C:\Users\Ady\Documents\toolchains\zig-master\current\zig.exe'
    if ($env:OPENCLAW_ZIG_BIN -and $env:OPENCLAW_ZIG_BIN.Trim().Length -gt 0) {
        if (-not (Test-Path $env:OPENCLAW_ZIG_BIN)) {
            throw "OPENCLAW_ZIG_BIN is set but not found: $($env:OPENCLAW_ZIG_BIN)"
        }
        return $env:OPENCLAW_ZIG_BIN
    }

    $zigCmd = Get-Command zig -ErrorAction SilentlyContinue
    if ($null -ne $zigCmd -and $zigCmd.Path) {
        return $zigCmd.Path
    }

    if (Test-Path $defaultWindowsZig) {
        return $defaultWindowsZig
    }

    throw 'Zig executable not found. Set OPENCLAW_ZIG_BIN or ensure `zig` is on PATH.'
}

function Resolve-Executable {
    param(
        [string[]] $Candidates
    )

    foreach ($candidate in $Candidates) {
        $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($null -ne $cmd -and $cmd.Path) {
            return $cmd.Path
        }
        if (Test-Path $candidate) {
            return (Resolve-Path $candidate).Path
        }
    }

    return $null
}

function New-RawDiskImage {
    param(
        [string] $Path,
        [int] $SizeMiB
    )

    if (Test-Path $Path) {
        Remove-Item -Force $Path
    }
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::ReadWrite)
    try {
        $stream.SetLength([int64]$SizeMiB * 1MB)
    } finally {
        $stream.Dispose()
    }
}

function Read-ImageU32LE {
    param(
        [byte[]] $Bytes,
        [uint32] $Lba
    )

    return [System.BitConverter]::ToUInt32($Bytes, [int]$Lba * $blockSize)
}

Set-Location $repo
New-Item -ItemType Directory -Force -Path $releaseDir | Out-Null

$zig = Resolve-ZigExecutable
$qemu = Resolve-Executable @('qemu-system-i386', 'qemu-system-i386.exe', 'C:\Program Files\qemu\qemu-system-i386.exe')
$clang = Resolve-Executable @('clang', 'clang.exe', 'C:\Users\Ady\Documents\starpro\tooling\emsdk\upstream\bin\clang.exe')
$zigGlobalCacheDir = if ($env:ZIG_GLOBAL_CACHE_DIR -and $env:ZIG_GLOBAL_CACHE_DIR.Trim().Length -gt 0) { $env:ZIG_GLOBAL_CACHE_DIR } else { Join-Path $repo '.zig-global-cache-virtio-block-mount-probe' }
$zigLocalCacheDir = if ($env:ZIG_LOCAL_CACHE_DIR -and $env:ZIG_LOCAL_CACHE_DIR.Trim().Length -gt 0) { $env:ZIG_LOCAL_CACHE_DIR } else { Join-Path $repo '.zig-cache-virtio-block-mount-probe' }

if ($null -eq $qemu) {
    Write-Output 'BAREMETAL_I386_QEMU_AVAILABLE=False'
    Write-Output 'BAREMETAL_I386_QEMU_VIRTIO_BLOCK_MOUNT_PROBE=skipped'
    return
}

if ($null -eq $clang) {
    Write-Output 'BAREMETAL_I386_QEMU_AVAILABLE=True'
    Write-Output "BAREMETAL_I386_QEMU_BINARY=$qemu"
    Write-Output 'BAREMETAL_I386_QEMU_PVH_TOOLCHAIN_AVAILABLE=False'
    Write-Output 'BAREMETAL_I386_QEMU_PVH_MISSING=clang'
    Write-Output 'BAREMETAL_I386_QEMU_VIRTIO_BLOCK_MOUNT_PROBE=skipped'
    return
}

$optionsPath = Join-Path $releaseDir 'qemu-virtio-block-mount-probe-options.zig'
$mainObj = Join-Path $releaseDir 'openclaw-zig-baremetal-main-virtio-block-mount-probe.o'
$bootObj = Join-Path $releaseDir 'openclaw-zig-pvh-boot-virtio-block-mount-probe.o'
$artifact = Join-Path $releaseDir 'openclaw-zig-baremetal-pvh-virtio-block-mount-probe.elf'
$diskImage = Join-Path $releaseDir 'qemu-virtio-block-mount-probe.img'
$bootSource = Join-Path $repo 'scripts\baremetal\pvh_boot.S'
$linkerScript = Join-Path $repo 'scripts\baremetal\pvh_lld.ld'
$stdoutPath = Join-Path $releaseDir 'qemu-virtio-block-mount-probe.stdout.log'
$stderrPath = Join-Path $releaseDir 'qemu-virtio-block-mount-probe.stderr.log'

if (-not $SkipBuild) {
    & $zig build baremetal-i386 -Doptimize=ReleaseSafe -Dbaremetal-virtio-block-mount-probe=true --summary all
    if ($LASTEXITCODE -ne 0) { throw "zig build baremetal-i386 virtio-block mount probe failed with exit code $LASTEXITCODE" }
}

$artifactCandidates = @(
    (Join-Path $repo 'zig-out\\bin\\openclaw-zig-baremetal-i386.elf'),
    (Join-Path $repo 'zig-out\\openclaw-zig-baremetal-i386.elf'),
    (Join-Path $repo 'zig-out/openclaw-zig-baremetal-i386.elf')
)
$artifact = $null
foreach ($candidate in $artifactCandidates) {
    if (Test-Path $candidate) {
        $artifact = (Resolve-Path $candidate).Path
        break
    }
}
if ($null -eq $artifact) { throw 'i386 virtio-block mount probe artifact not found after build.' }

New-RawDiskImage -Path $diskImage -SizeMiB $DiskSizeMiB
if (Test-Path $stdoutPath) { Remove-Item -Force $stdoutPath }
if (Test-Path $stderrPath) { Remove-Item -Force $stderrPath }

$qemuArgs = @(
    '-kernel', $artifact,
    '-drive', "file=$diskImage,if=none,id=drv0,format=raw",
    '-device', 'virtio-blk-pci,drive=drv0,disable-legacy=on',
    '-nographic',
    '-no-reboot',
    '-no-shutdown',
    '-serial', 'none',
    '-monitor', 'none',
    '-device', 'isa-debug-exit,iobase=0xf4,iosize=0x04'
)

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $qemu
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.Arguments = (($qemuArgs | ForEach-Object {
    if ("$_" -match '[\s"]') {
        '"{0}"' -f (($_ -replace '"', '\"'))
    } else {
        "$_"
    }
}) -join ' ')

$proc = New-Object System.Diagnostics.Process
$proc.StartInfo = $psi
[void]$proc.Start()
$stdoutTask = $proc.StandardOutput.ReadToEndAsync()
$stderrTask = $proc.StandardError.ReadToEndAsync()

if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
    try { $proc.Kill($true) } catch {}
    throw "QEMU i386 virtio-block mount probe timed out after $TimeoutSeconds seconds."
}

$proc.WaitForExit()
$stdout = $stdoutTask.GetAwaiter().GetResult()
$stderr = $stderrTask.GetAwaiter().GetResult()
Set-Content -Path $stdoutPath -Value $stdout -Encoding Ascii
Set-Content -Path $stderrPath -Value $stderr -Encoding Ascii
$exitCode = $proc.ExitCode
if ($exitCode -ne $expectedExitCode) {
    $probeCode = [int](($exitCode - 1) / 2)
    throw ("QEMU i386 virtio-block mount probe failed with exit code {0} (probe code 0x{1:X2})." -f $exitCode, $probeCode)
}

$imageBytes = [System.IO.File]::ReadAllBytes($diskImage)
$toolMagic = Read-ImageU32LE -Bytes $imageBytes -Lba 0
$fsMagic = Read-ImageU32LE -Bytes $imageBytes -Lba $filesystemSuperblockLba
$imageText = [System.Text.Encoding]::ASCII.GetString($imageBytes)

if ($toolMagic -ne $toolLayoutMagic) {
    throw ("i386 virtio-block mount tool-layout superblock magic mismatch. Expected 0x{0:X8}, got 0x{1:X8}." -f $toolLayoutMagic, $toolMagic)
}
if ($fsMagic -ne $filesystemMagic) {
    throw ("i386 virtio-block mount filesystem superblock magic mismatch. Expected 0x{0:X8}, got 0x{1:X8}." -f $filesystemMagic, $fsMagic)
}
if (-not $imageText.Contains($expectedLoaderMarker)) {
    throw "i386 virtio-block mount image does not contain expected loader marker '$expectedLoaderMarker'."
}
if (-not $imageText.Contains($expectedBootMountRegistryMarker)) {
    throw "i386 virtio-block mount image does not contain expected boot registry marker '$expectedBootMountRegistryMarker'."
}
if (-not $imageText.Contains($expectedMountRegistryMarker)) {
    throw "i386 virtio-block mount image does not contain expected registry marker '$expectedMountRegistryMarker'."
}
if (-not $imageText.Contains($expectedCacheMountRegistryMarker)) {
    throw "i386 virtio-block mount image does not contain expected cache registry marker '$expectedCacheMountRegistryMarker'."
}
if (-not $imageText.Contains($expectedMountPayloadMarker)) {
    throw "i386 virtio-block mount image does not contain expected payload marker '$expectedMountPayloadMarker'."
}

Write-Output 'BAREMETAL_I386_QEMU_AVAILABLE=True'
Write-Output "BAREMETAL_I386_QEMU_BINARY=$qemu"
Write-Output 'BAREMETAL_I386_QEMU_VIRTIO_BLOCK_MOUNT_PROBE=pass'
Write-Output "BAREMETAL_I386_QEMU_VIRTIO_BLOCK_MOUNT_IMAGE=$diskImage"
Write-Output ("BAREMETAL_VIRTIO_BLOCK_MOUNT_TOOL_LAYOUT_MAGIC=0x{0:X8}" -f $toolMagic)
Write-Output ("BAREMETAL_VIRTIO_BLOCK_MOUNT_FILESYSTEM_MAGIC=0x{0:X8}" -f $fsMagic)
Write-Output "BAREMETAL_VIRTIO_BLOCK_MOUNT_LOADER_MARKER=$expectedLoaderMarker"
Write-Output "BAREMETAL_VIRTIO_BLOCK_MOUNT_BOOT_REGISTRY_MARKER=$expectedBootMountRegistryMarker"
Write-Output "BAREMETAL_VIRTIO_BLOCK_MOUNT_REGISTRY_MARKER=$expectedMountRegistryMarker"
Write-Output "BAREMETAL_VIRTIO_BLOCK_MOUNT_CACHE_REGISTRY_MARKER=$expectedCacheMountRegistryMarker"
Write-Output "BAREMETAL_VIRTIO_BLOCK_MOUNT_PAYLOAD_MARKER=$expectedMountPayloadMarker"

