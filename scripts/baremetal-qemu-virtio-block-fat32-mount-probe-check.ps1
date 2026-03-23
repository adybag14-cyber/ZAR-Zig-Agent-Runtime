# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 30,
    [int] $DiskSizeMiB = 8
)

$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$releaseDir = Join-Path $repo 'release'
$expectedProbeCode = 0x5C
$expectedExitCode = ($expectedProbeCode * 2) + 1
$expectedPayloadMarker = 'hello-from-fat32'
$expectedNestedPayloadMarker = 'hello-from-fat32-subdir'
$fat32TypeOffset = 82
$bootSignatureOffset = 510

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
    param([string[]] $Candidates)
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
    param([string] $Path, [int] $SizeMiB)
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

Set-Location $repo
New-Item -ItemType Directory -Force -Path $releaseDir | Out-Null

$zig = Resolve-ZigExecutable
$qemu = Resolve-Executable @('qemu-system-x86_64', 'qemu-system-x86_64.exe', 'C:\Program Files\qemu\qemu-system-x86_64.exe')
$clang = Resolve-Executable @('clang', 'clang.exe', 'C:\Users\Ady\Documents\starpro\tooling\emsdk\upstream\bin\clang.exe')
$zigGlobalCacheDir = if ($env:ZIG_GLOBAL_CACHE_DIR -and $env:ZIG_GLOBAL_CACHE_DIR.Trim().Length -gt 0) { $env:ZIG_GLOBAL_CACHE_DIR } else { Join-Path $repo '.zig-global-cache-virtio-block-fat32-mount-probe' }
$zigLocalCacheDir = if ($env:ZIG_LOCAL_CACHE_DIR -and $env:ZIG_LOCAL_CACHE_DIR.Trim().Length -gt 0) { $env:ZIG_LOCAL_CACHE_DIR } else { Join-Path $repo '.zig-cache-virtio-block-fat32-mount-probe' }

if ($null -eq $qemu) {
    Write-Output 'BAREMETAL_QEMU_AVAILABLE=False'
    Write-Output 'BAREMETAL_QEMU_VIRTIO_BLOCK_FAT32_MOUNT_PROBE=skipped'
    return
}

if ($null -eq $clang) {
    Write-Output 'BAREMETAL_QEMU_AVAILABLE=True'
    Write-Output "BAREMETAL_QEMU_BINARY=$qemu"
    Write-Output 'BAREMETAL_QEMU_PVH_TOOLCHAIN_AVAILABLE=False'
    Write-Output 'BAREMETAL_QEMU_PVH_MISSING=clang'
    Write-Output 'BAREMETAL_QEMU_VIRTIO_BLOCK_FAT32_MOUNT_PROBE=skipped'
    return
}

$optionsPath = Join-Path $releaseDir 'qemu-virtio-block-fat32-mount-probe-options.zig'
$mainObj = Join-Path $releaseDir 'openclaw-zig-baremetal-main-virtio-block-fat32-mount-probe.o'
$bootObj = Join-Path $releaseDir 'openclaw-zig-pvh-boot-virtio-block-fat32-mount-probe.o'
$artifact = Join-Path $releaseDir 'openclaw-zig-baremetal-pvh-virtio-block-fat32-mount-probe.elf'
$diskImage = Join-Path $releaseDir 'qemu-virtio-block-fat32-mount-probe.img'
$bootSource = Join-Path $repo 'scripts\baremetal\pvh_boot.S'
$linkerScript = Join-Path $repo 'scripts\baremetal\pvh_lld.ld'
$stdoutPath = Join-Path $releaseDir 'qemu-virtio-block-fat32-mount-probe.stdout.log'
$stderrPath = Join-Path $releaseDir 'qemu-virtio-block-fat32-mount-probe.stderr.log'

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
pub const virtio_block_probe: bool = false;
pub const virtio_block_installer_probe: bool = false;
pub const virtio_block_mount_probe: bool = false;
pub const virtio_block_ext2_mount_probe: bool = false;
pub const virtio_block_fat32_mount_probe: bool = true;
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
pub const virtio_net_probe: bool = false;
pub const virtio_net_arp_probe: bool = false;
pub const virtio_net_ipv4_probe: bool = false;
pub const virtio_net_udp_probe: bool = false;
pub const virtio_net_tcp_probe: bool = false;
pub const virtio_net_dhcp_probe: bool = false;
pub const virtio_net_dns_probe: bool = false;
pub const virtio_net_http_post_probe: bool = false;
pub const virtio_net_https_post_probe: bool = false;
pub const virtio_net_tool_service_probe: bool = false;
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

    & $zig build-obj -fno-strip -fsingle-threaded -OReleaseSafe -target x86_64-freestanding-none -mcpu baseline --dep build_options "-Mroot=$repo\src\baremetal_main.zig" "-Mbuild_options=$optionsPath" --cache-dir "$zigLocalCacheDir" --global-cache-dir "$zigGlobalCacheDir" --name 'openclaw-zig-baremetal-main-virtio-block-fat32-mount-probe' "-femit-bin=$mainObj"
    if ($LASTEXITCODE -ne 0) { throw "zig build-obj for virtio-block fat32 mount probe failed with exit code $LASTEXITCODE" }

    & $clang -c -target x86_64-unknown-elf $bootSource -o $bootObj
    if ($LASTEXITCODE -ne 0) { throw "clang assemble for virtio-block fat32 mount PVH shim failed with exit code $LASTEXITCODE" }

    & $zig build-exe $mainObj $bootObj -ODebug -target x86_64-freestanding-none "-T$linkerScript" -fcompiler-rt -fno-strip --cache-dir "$zigLocalCacheDir" --global-cache-dir "$zigGlobalCacheDir" "-femit-bin=$artifact"
    if ($LASTEXITCODE -ne 0) { throw "zig final link for virtio-block fat32 mount PVH artifact failed with exit code $LASTEXITCODE" }
}

if (-not (Test-Path $artifact)) {
    throw "Virtio-block fat32 mount probe artifact is missing: $artifact"
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
$psi.Arguments = (($qemuArgs | ForEach-Object { if ("$_" -match '[\s"]') { '"{0}"' -f (($_ -replace '"', '\"')) } else { "$_" } }) -join ' ')

$proc = New-Object System.Diagnostics.Process
$proc.StartInfo = $psi
[void]$proc.Start()
$stdoutTask = $proc.StandardOutput.ReadToEndAsync()
$stderrTask = $proc.StandardError.ReadToEndAsync()

if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
    try { $proc.Kill($true) } catch {}
    throw "QEMU virtio-block fat32 mount probe timed out after $TimeoutSeconds seconds."
}

$proc.WaitForExit()
$stdout = $stdoutTask.GetAwaiter().GetResult()
$stderr = $stderrTask.GetAwaiter().GetResult()
Set-Content -Path $stdoutPath -Value $stdout -Encoding Ascii
Set-Content -Path $stderrPath -Value $stderr -Encoding Ascii
if ($proc.ExitCode -ne $expectedExitCode) {
    $probeCode = [int](($proc.ExitCode - 1) / 2)
    throw ("QEMU virtio-block fat32 mount probe failed with exit code {0} (probe code 0x{1:X2})." -f $proc.ExitCode, $probeCode)
}

$imageBytes = [System.IO.File]::ReadAllBytes($diskImage)
$bootSig = [System.BitConverter]::ToUInt16($imageBytes, $bootSignatureOffset)
$fat32Type = [System.Text.Encoding]::ASCII.GetString($imageBytes, $fat32TypeOffset, 8)
$imageText = [System.Text.Encoding]::ASCII.GetString($imageBytes)
if ($bootSig -ne 0xAA55) {
    throw ("Virtio-block fat32 mount probe boot signature mismatch. Expected 0xAA55, got 0x{0:X4}." -f $bootSig)
}
if ($fat32Type -ne 'FAT32   ') {
    throw "Virtio-block fat32 mount probe type marker mismatch. Expected 'FAT32   ', got '$fat32Type'."
}
if (-not $imageText.Contains($expectedPayloadMarker)) {
    throw "Virtio-block fat32 mount image does not contain expected payload marker '$expectedPayloadMarker'."
}
if (-not $imageText.Contains($expectedNestedPayloadMarker)) {
    throw "Virtio-block fat32 mount image does not contain expected nested payload marker '$expectedNestedPayloadMarker'."
}

Write-Output 'BAREMETAL_QEMU_AVAILABLE=True'
Write-Output "BAREMETAL_QEMU_BINARY=$qemu"
Write-Output 'BAREMETAL_QEMU_VIRTIO_BLOCK_FAT32_MOUNT_PROBE=pass'
Write-Output "BAREMETAL_QEMU_VIRTIO_BLOCK_FAT32_MOUNT_IMAGE=$diskImage"
Write-Output ('BAREMETAL_VIRTIO_BLOCK_FAT32_BOOT_SIG=0x{0:X4}' -f $bootSig)
Write-Output "BAREMETAL_VIRTIO_BLOCK_FAT32_TYPE=$fat32Type"
Write-Output "BAREMETAL_VIRTIO_BLOCK_FAT32_PAYLOAD_MARKER=$expectedPayloadMarker"
Write-Output "BAREMETAL_VIRTIO_BLOCK_FAT32_NESTED_PAYLOAD_MARKER=$expectedNestedPayloadMarker"
