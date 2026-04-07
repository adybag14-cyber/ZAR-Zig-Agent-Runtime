# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 30,
    [int] $DiskSizeMiB = 8
)

$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$releaseDir = Join-Path $repo 'release'
$expectedProbeCode = 0x4F
$expectedExitCode = ($expectedProbeCode * 2) + 1
$rawProbeLba = 300
$rawProbeSeed = 0x56
$toolSlotLba = 34
$toolSlotSeed = 0x68
$filesystemSuperblockLba = 130
$toolLayoutMagic = 0x4f43544c
$filesystemMagic = 0x4f434653
$blockSize = 512

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

function Resolve-QemuExecutable {
    $candidates = @(
        'qemu-system-x86_64',
        'qemu-system-x86_64.exe',
        'C:\Program Files\qemu\qemu-system-x86_64.exe'
    )

    foreach ($name in $candidates) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($null -ne $cmd -and $cmd.Path) {
            return $cmd.Path
        }
        if (Test-Path $name) {
            return (Resolve-Path $name).Path
        }
    }

    return $null
}

function Resolve-ClangExecutable {
    $candidates = @(
        'clang',
        'clang.exe',
        'C:\Users\Ady\Documents\starpro\tooling\emsdk\upstream\bin\clang.exe'
    )

    foreach ($name in $candidates) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($null -ne $cmd -and $cmd.Path) {
            return $cmd.Path
        }
        if (Test-Path $name) {
            return (Resolve-Path $name).Path
        }
    }

    return $null
}

function Resolve-LldExecutable {
    $candidates = @(
        'lld',
        'lld.exe',
        'C:\Users\Ady\Documents\starpro\tooling\emsdk\upstream\bin\lld.exe'
    )

    foreach ($name in $candidates) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($null -ne $cmd -and $cmd.Path) {
            return $cmd.Path
        }
        if (Test-Path $name) {
            return (Resolve-Path $name).Path
        }
    }

    return $null
}

function Resolve-ZigGlobalCacheDir {
    $candidates = @()
    if ($env:ZIG_GLOBAL_CACHE_DIR -and $env:ZIG_GLOBAL_CACHE_DIR.Trim().Length -gt 0) {
        $candidates += $env:ZIG_GLOBAL_CACHE_DIR
    }
    if ($env:LOCALAPPDATA -and $env:LOCALAPPDATA.Trim().Length -gt 0) {
        $candidates += (Join-Path $env:LOCALAPPDATA 'zig')
    }
    if ($env:XDG_CACHE_HOME -and $env:XDG_CACHE_HOME.Trim().Length -gt 0) {
        $candidates += (Join-Path $env:XDG_CACHE_HOME 'zig')
    }
    if ($env:HOME -and $env:HOME.Trim().Length -gt 0) {
        $candidates += (Join-Path $env:HOME '.cache/zig')
    }

    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            return $candidate
        }
    }

    return (Join-Path $repo '.zig-global-cache')
}

function Resolve-TemporaryRoot {
    $candidates = @(
        $env:TEMP,
        $env:TMPDIR,
        $env:TMP,
        [System.IO.Path]::GetTempPath()
    )

    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            return $candidate
        }
    }

    throw 'Temporary directory is not available.'
}

function Test-CompilerRtArchiveElf64X86 {
    param(
        [string] $ArchivePath
    )

    if (-not (Test-Path $ArchivePath)) {
        return $false
    }

    $memberName = (& $zig ar t $ArchivePath 2>$null | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace($memberName)) {
        return $false
    }

    $scratchRoot = Join-Path (Resolve-TemporaryRoot) 'zar-zig-probe-compiler-rt'
    $scratchDir = Join-Path $scratchRoot ([System.Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $scratchDir | Out-Null
    try {
        Push-Location $scratchDir
        try {
            & $zig ar x $ArchivePath $memberName 2>$null | Out-Null
        } finally {
            Pop-Location
        }
        $memberPath = Join-Path $scratchDir $memberName
        if (-not (Test-Path $memberPath)) {
            return $false
        }
        $bytes = [System.IO.File]::ReadAllBytes($memberPath)
        if ($bytes.Length -lt 20) {
            return $false
        }
        $isElf = ($bytes[0] -eq 0x7F -and $bytes[1] -eq 0x45 -and $bytes[2] -eq 0x4C -and $bytes[3] -eq 0x46)
        $isElf64 = ($bytes[4] -eq 2)
        $isLittleEndian = ($bytes[5] -eq 1)
        $machine = [System.BitConverter]::ToUInt16($bytes, 18)
        return ($isElf -and $isElf64 -and $isLittleEndian -and $machine -eq 62)
    } finally {
        if (Test-Path $scratchDir) {
            Remove-Item -Force -Recurse $scratchDir
        }
    }
}

function Resolve-CompilerRtArchive {
    param(
        [string[]] $CacheRoots
    )

    foreach ($cacheRoot in $CacheRoots) {
        if ([string]::IsNullOrWhiteSpace($cacheRoot)) {
            continue
        }
        $objRoot = Join-Path $cacheRoot 'o'
        if (-not (Test-Path $objRoot)) {
            continue
        }

        $candidates = Get-ChildItem -Path $objRoot -Recurse -Filter 'libcompiler_rt.a' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending

        foreach ($candidate in $candidates) {
            if (Test-CompilerRtArchiveElf64X86 -ArchivePath $candidate.FullName) {
                return $candidate.FullName
            }
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

function Read-ImageByte {
    param(
        [byte[]] $Bytes,
        [uint32] $Lba,
        [uint32] $Offset
    )

    $index = ([int]$Lba * $blockSize) + [int]$Offset
    return [int]$Bytes[$index]
}

function Read-ImageU32LE {
    param(
        [byte[]] $Bytes,
        [uint32] $Lba
    )

    $index = [int]$Lba * $blockSize
    return [System.BitConverter]::ToUInt32($Bytes, $index)
}

Set-Location $repo
New-Item -ItemType Directory -Force -Path $releaseDir | Out-Null

$zig = Resolve-ZigExecutable
$qemu = Resolve-QemuExecutable
$clang = Resolve-ClangExecutable
$zigGlobalCacheDir = if ($env:ZIG_GLOBAL_CACHE_DIR -and $env:ZIG_GLOBAL_CACHE_DIR.Trim().Length -gt 0) { $env:ZIG_GLOBAL_CACHE_DIR } else { Join-Path $repo '.zig-global-cache-virtio-block-probe' }
$zigLocalCacheDir = if ($env:ZIG_LOCAL_CACHE_DIR -and $env:ZIG_LOCAL_CACHE_DIR.Trim().Length -gt 0) { $env:ZIG_LOCAL_CACHE_DIR } else { Join-Path $repo '.zig-cache-virtio-block-probe' }

if ($null -eq $qemu) {
    Write-Output 'BAREMETAL_QEMU_AVAILABLE=False'
    Write-Output 'BAREMETAL_QEMU_VIRTIO_BLOCK_PROBE=skipped'
    return
}

if ($null -eq $clang) {
    Write-Output 'BAREMETAL_QEMU_AVAILABLE=True'
    Write-Output "BAREMETAL_QEMU_BINARY=$qemu"
    Write-Output 'BAREMETAL_QEMU_PVH_TOOLCHAIN_AVAILABLE=False'
    if ($null -eq $clang) { Write-Output 'BAREMETAL_QEMU_PVH_MISSING=clang' }
    Write-Output 'BAREMETAL_QEMU_VIRTIO_BLOCK_PROBE=skipped'
    return
}

$optionsPath = Join-Path $releaseDir 'qemu-virtio-block-probe-options.zig'
$rootModulePath = (Join-Path $repo "src/baremetal_main.zig").Replace('\\', '/')
$optionsModulePath = $optionsPath.Replace('\\', '/')
$mainObj = Join-Path $releaseDir 'openclaw-zig-baremetal-main-virtio-block-probe.o'
$bootObj = Join-Path $releaseDir 'openclaw-zig-pvh-boot-virtio-block-probe.o'
$artifact = Join-Path $releaseDir 'openclaw-zig-baremetal-pvh-virtio-block-probe.elf'
$diskImage = Join-Path $releaseDir 'qemu-virtio-block-probe.img'
$bootSource = Join-Path $repo 'scripts\baremetal\pvh_boot.S'
$linkerScript = Join-Path $repo 'scripts\baremetal\pvh_lld.ld'
$stdoutPath = Join-Path $releaseDir 'qemu-virtio-block-probe.stdout.log'
$stderrPath = Join-Path $releaseDir 'qemu-virtio-block-probe.stderr.log'

if (-not $SkipBuild) {
    New-Item -ItemType Directory -Force -Path $zigGlobalCacheDir | Out-Null
    New-Item -ItemType Directory -Force -Path $zigLocalCacheDir | Out-Null
@"
pub const qemu_smoke: bool = false;
pub const console_probe_banner: bool = false;
pub const framebuffer_probe_banner: bool = false;
pub const ata_storage_probe: bool = false;
pub const ata_gpt_installer_probe: bool = false;
pub const virtio_gpu_display_probe: bool = false;
pub const virtio_block_probe: bool = true;
pub const e1000_probe: bool = false;
pub const e1000_arp_probe: bool = false;
pub const e1000_ipv4_probe: bool = false;
pub const e1000_udp_probe: bool = false;
pub const e1000_tcp_probe: bool = false;
pub const e1000_dhcp_probe: bool = false;
pub const e1000_dns_probe: bool = false;
pub const e1000_http_post_probe: bool = false;
pub const e1000_https_post_probe: bool = false;
pub const e1000_tool_service_probe: bool = false;
pub const rtl8139_probe: bool = false;
pub const rtl8139_arp_probe: bool = false;
pub const rtl8139_ipv4_probe: bool = false;
pub const rtl8139_udp_probe: bool = false;
pub const rtl8139_tcp_probe: bool = false;
pub const rtl8139_dhcp_probe: bool = false;
pub const rtl8139_dns_probe: bool = false;
pub const rtl8139_gateway_probe: bool = false;
pub const rtl8139_http_post_probe: bool = false;
pub const rtl8139_https_post_probe: bool = false;
pub const rtl8139_runtime_service_probe: bool = false;
pub const tool_exec_probe: bool = false;
pub const tool_runtime_probe: bool = false;
"@ | Set-Content -Path $optionsPath -Encoding Ascii

    & $zig build-obj `
        -fno-strip `
        -fsingle-threaded `
        -OReleaseSafe `
        -target x86_64-freestanding-none `
        -mcpu baseline `
        --dep build_options `
        "-Mroot=$rootModulePath" `
        "-Mbuild_options=$optionsModulePath" `
        --cache-dir "$zigLocalCacheDir" `
        --global-cache-dir "$zigGlobalCacheDir" `
        --name 'openclaw-zig-baremetal-main-virtio-block-probe' `
        "-femit-bin=$mainObj"
    if ($LASTEXITCODE -ne 0) {
        throw "zig build-obj for virtio-block probe failed with exit code $LASTEXITCODE"
    }

    & $clang -c -target x86_64-unknown-elf $bootSource -o $bootObj
    if ($LASTEXITCODE -ne 0) {
        throw "clang assemble for virtio-block PVH shim failed with exit code $LASTEXITCODE"
    }

    & $zig build-exe `
        $mainObj `
        $bootObj `
        -ODebug `
        -target x86_64-freestanding-none `
        "-T$linkerScript" `
        -fcompiler-rt `
        -fno-strip `
        --cache-dir "$zigLocalCacheDir" `
        --global-cache-dir "$zigGlobalCacheDir" `
        "-femit-bin=$artifact"
    if ($LASTEXITCODE -ne 0) {
        throw "zig final link for virtio-block PVH artifact failed with exit code $LASTEXITCODE"
    }
}

if (-not (Test-Path $artifact)) {
    throw "Virtio-block probe artifact is missing: $artifact"
}

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
    throw "QEMU virtio-block probe timed out after $TimeoutSeconds seconds."
}

$proc.WaitForExit()
$stdout = $stdoutTask.GetAwaiter().GetResult()
$stderr = $stderrTask.GetAwaiter().GetResult()
Set-Content -Path $stdoutPath -Value $stdout -Encoding Ascii
Set-Content -Path $stderrPath -Value $stderr -Encoding Ascii
$exitCode = $proc.ExitCode
if ($exitCode -ne $expectedExitCode) {
    $probeCode = [int](($exitCode - 1) / 2)
    throw ("QEMU virtio-block probe failed with exit code {0} (probe code 0x{1:X2})." -f $exitCode, $probeCode)
}

$imageBytes = [System.IO.File]::ReadAllBytes($diskImage)
$rawByte0 = Read-ImageByte -Bytes $imageBytes -Lba $rawProbeLba -Offset 0
$rawByte1 = Read-ImageByte -Bytes $imageBytes -Lba $rawProbeLba -Offset 1
$rawNextBlockByte0 = Read-ImageByte -Bytes $imageBytes -Lba ($rawProbeLba + 1) -Offset 0
$toolByte0 = Read-ImageByte -Bytes $imageBytes -Lba $toolSlotLba -Offset 0
$toolByte1 = Read-ImageByte -Bytes $imageBytes -Lba $toolSlotLba -Offset 1
$toolByte512 = Read-ImageByte -Bytes $imageBytes -Lba ($toolSlotLba + 1) -Offset 0
$toolMagic = Read-ImageU32LE -Bytes $imageBytes -Lba 0
$fsMagic = Read-ImageU32LE -Bytes $imageBytes -Lba $filesystemSuperblockLba

if ($rawByte0 -ne $rawProbeSeed -or $rawByte1 -ne ($rawProbeSeed + 1) -or $rawNextBlockByte0 -ne $rawProbeSeed) {
    throw 'Host-side virtio-block raw readback did not match the expected pattern.'
}
if ($toolByte0 -ne $toolSlotSeed -or $toolByte1 -ne ($toolSlotSeed + 1) -or $toolByte512 -ne $toolSlotSeed) {
    throw 'Host-side virtio-block tool slot payload did not match the expected persisted pattern.'
}
if ($toolMagic -ne $toolLayoutMagic) {
    throw ("Virtio-block tool-layout superblock magic mismatch. Expected 0x{0:X8}, got 0x{1:X8}." -f $toolLayoutMagic, $toolMagic)
}
if ($fsMagic -ne $filesystemMagic) {
    throw ("Virtio-block filesystem superblock magic mismatch. Expected 0x{0:X8}, got 0x{1:X8}." -f $filesystemMagic, $fsMagic)
}

Write-Output 'BAREMETAL_QEMU_AVAILABLE=True'
Write-Output "BAREMETAL_QEMU_BINARY=$qemu"
Write-Output 'BAREMETAL_QEMU_VIRTIO_BLOCK_PROBE=pass'
Write-Output "BAREMETAL_QEMU_VIRTIO_BLOCK_IMAGE=$diskImage"
Write-Output "BAREMETAL_VIRTIO_BLOCK_RAW_LBA300_BYTE0=$rawByte0"
Write-Output "BAREMETAL_VIRTIO_BLOCK_RAW_LBA300_BYTE1=$rawByte1"
Write-Output "BAREMETAL_VIRTIO_BLOCK_RAW_LBA301_BYTE0=$rawNextBlockByte0"
Write-Output "BAREMETAL_VIRTIO_BLOCK_TOOL_SLOT_BYTE0=$toolByte0"
Write-Output "BAREMETAL_VIRTIO_BLOCK_TOOL_SLOT_BYTE1=$toolByte1"
Write-Output "BAREMETAL_VIRTIO_BLOCK_TOOL_SLOT_BYTE512=$toolByte512"
Write-Output ("BAREMETAL_VIRTIO_BLOCK_TOOL_LAYOUT_MAGIC=0x{0:X8}" -f $toolMagic)
Write-Output ("BAREMETAL_VIRTIO_BLOCK_FILESYSTEM_MAGIC=0x{0:X8}" -f $fsMagic)
