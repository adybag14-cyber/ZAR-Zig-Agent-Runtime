# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 30,
    [int] $DiskSizeMiB = 8
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$releaseDir = Join-Path $repo 'release'
$expectedProbeCode = 0x34
$expectedExitCode = ($expectedProbeCode * 2) + 1
$partitionStartLba = 2048
$partitionSectorCount = 4096
$secondaryPartitionStartLba = 8192
$secondaryPartitionSectorCount = 2048
$partitionType = 0x83
$rawProbeLba = 300
$rawProbeSeed = 0x41
$secondaryRawProbeLba = 12
$secondaryRawProbeSeed = 0x53
$toolSlotLba = 34
$toolSlotSeed = 0x30
$secondaryToolSlotSeed = 0x60
$filesystemSuperblockLba = 130
$toolLayoutMagic = 0x4f43544c
$filesystemMagic = 0x4f434653
$blockSize = 512

function Resolve-ZigExecutable {
    $default = 'C:\Users\Ady\Documents\toolchains\zig-master\current\zig.exe'
    if ($env:OPENCLAW_ZIG_BIN -and $env:OPENCLAW_ZIG_BIN.Trim().Length -gt 0) {
        if (-not (Test-Path $env:OPENCLAW_ZIG_BIN)) { throw "OPENCLAW_ZIG_BIN not found: $($env:OPENCLAW_ZIG_BIN)" }
        return $env:OPENCLAW_ZIG_BIN
    }
    $cmd = Get-Command zig -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Path) { return $cmd.Path }
    if (Test-Path $default) { return $default }
    throw 'Zig executable not found.'
}

function Resolve-QemuExecutable {
    $candidates = @(
        'qemu-system-i386',
        'qemu-system-i386.exe',
        'C:\Program Files\qemu\qemu-system-i386.exe'
    )
    foreach ($name in $candidates) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd -and $cmd.Path) { return $cmd.Path }
        if (Test-Path $name) { return (Resolve-Path $name).Path }
    }
    return $null
}

function New-RawDiskImage($Path, $SizeMiB) {
    if (Test-Path $Path) { Remove-Item -Force $Path }
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::ReadWrite)
    try { $stream.SetLength([int64]$SizeMiB * 1MB) } finally { $stream.Dispose() }
}

function Write-ImageU32LE([byte[]] $Bytes, [int] $Index, [uint32] $Value) {
    $Bytes[$Index + 0] = [byte]($Value -band 0xFF)
    $Bytes[$Index + 1] = [byte](($Value -shr 8) -band 0xFF)
    $Bytes[$Index + 2] = [byte](($Value -shr 16) -band 0xFF)
    $Bytes[$Index + 3] = [byte](($Value -shr 24) -band 0xFF)
}

function Read-ImageByte([byte[]] $Bytes, [uint32] $Lba, [uint32] $Offset) {
    $index = ([int]$Lba * $blockSize) + [int]$Offset
    return [int]$Bytes[$index]
}

function Read-ImageU32LE([byte[]] $Bytes, [uint32] $Lba) {
    $index = [int]$Lba * $blockSize
    return [System.BitConverter]::ToUInt32($Bytes, $index)
}

function Initialize-MbrPartitionedImage {
    param([string] $Path)
    New-RawDiskImage -Path $Path -SizeMiB $DiskSizeMiB
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $entryOffset0 = 446
    $bytes[$entryOffset0 + 4] = $partitionType
    Write-ImageU32LE -Bytes $bytes -Index ($entryOffset0 + 8) -Value $partitionStartLba
    Write-ImageU32LE -Bytes $bytes -Index ($entryOffset0 + 12) -Value $partitionSectorCount
    $entryOffset1 = $entryOffset0 + 16
    $bytes[$entryOffset1 + 4] = $partitionType
    Write-ImageU32LE -Bytes $bytes -Index ($entryOffset1 + 8) -Value $secondaryPartitionStartLba
    Write-ImageU32LE -Bytes $bytes -Index ($entryOffset1 + 12) -Value $secondaryPartitionSectorCount
    $bytes[510] = 0x55
    $bytes[511] = 0xAA
    [System.IO.File]::WriteAllBytes($Path, $bytes)
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
if ($null -eq $qemu) {
    Write-Output 'BAREMETAL_I386_QEMU_AVAILABLE=False'
    Write-Output 'BAREMETAL_I386_QEMU_ATA_STORAGE_PROBE=skipped'
    return
}

if (-not $SkipBuild) {
    & $zig build baremetal-i386 -Doptimize=ReleaseFast -Dbaremetal-ata-storage-probe=true --prefix $buildPrefix --summary all
    if ($LASTEXITCODE -ne 0) { throw "zig build baremetal-i386 ata storage probe failed with exit code $LASTEXITCODE" }
}

$artifactCandidates = @(
    (Join-Path $buildPrefix 'bin\openclaw-zig-baremetal-i386.elf'),
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
if ($null -eq $artifact) { throw 'i386 ATA probe artifact not found after build.' }

$diskImage = Join-Path $releaseDir 'qemu-i386-ata-storage-probe.img'
$stdoutPath = Join-Path $releaseDir 'qemu-i386-ata-storage-probe.stdout.log'
$stderrPath = Join-Path $releaseDir 'qemu-i386-ata-storage-probe.stderr.log'
Initialize-MbrPartitionedImage -Path $diskImage
if (Test-Path $stdoutPath) { Remove-Item -Force $stdoutPath }
if (Test-Path $stderrPath) { Remove-Item -Force $stderrPath }

$qemuArgs = @(
    '-kernel', $artifact,
    '-nographic',
    '-no-reboot',
    '-no-shutdown',
    '-serial', 'none',
    '-monitor', 'none',
    '-drive', "file=$diskImage,if=ide,format=raw,index=0,media=disk",
    '-device', 'isa-debug-exit,iobase=0xf4,iosize=0x04'
)
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $qemu
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.Arguments = (($qemuArgs | ForEach-Object {
    if ("$_" -match '[\s"]') { '"{0}"' -f (($_ -replace '"', '\"')) } else { "$_" }
}) -join ' ')
$proc = New-Object System.Diagnostics.Process
$proc.StartInfo = $psi
[void]$proc.Start()
$stdoutTask = $proc.StandardOutput.ReadToEndAsync()
$stderrTask = $proc.StandardError.ReadToEndAsync()
if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
    try { $proc.Kill($true) } catch {}
    throw "QEMU i386 ATA storage probe timed out after $TimeoutSeconds seconds."
}
$proc.WaitForExit()
$stdout = $stdoutTask.GetAwaiter().GetResult()
$stderr = $stderrTask.GetAwaiter().GetResult()
Set-Content -Path $stdoutPath -Value $stdout -Encoding ascii
Set-Content -Path $stderrPath -Value $stderr -Encoding ascii
$exitCode = $proc.ExitCode
if ($exitCode -ne $expectedExitCode) {
    $probeCode = [int](($exitCode - 1) / 2)
    throw ("QEMU i386 ATA storage probe failed with exit code {0} (probe code 0x{1:X2})." -f $exitCode, $probeCode)
}

$bytes = [System.IO.File]::ReadAllBytes($diskImage)
$rawProbePhysicalLba = $partitionStartLba + $rawProbeLba
$secondaryRawProbePhysicalLba = $secondaryPartitionStartLba + $secondaryRawProbeLba
$toolSlotPhysicalLba = $partitionStartLba + $toolSlotLba
$secondaryToolSlotPhysicalLba = $secondaryPartitionStartLba + $toolSlotLba
$filesystemSuperblockPhysicalLba = $partitionStartLba + $filesystemSuperblockLba
if ((Read-ImageByte -Bytes $bytes -Lba $rawProbePhysicalLba -Offset 0) -ne $rawProbeSeed) { throw 'Primary raw ATA seed byte mismatch after i386 probe.' }
if ((Read-ImageByte -Bytes $bytes -Lba $secondaryRawProbePhysicalLba -Offset 0) -ne $secondaryRawProbeSeed) { throw 'Secondary raw ATA seed byte mismatch after i386 probe.' }
if ((Read-ImageByte -Bytes $bytes -Lba $toolSlotPhysicalLba -Offset 0) -ne $toolSlotSeed) { throw 'Primary tool slot seed mismatch after i386 probe.' }
if ((Read-ImageByte -Bytes $bytes -Lba $toolSlotPhysicalLba -Offset 512) -ne $toolSlotSeed) { throw 'Primary tool slot repeated seed mismatch after i386 probe.' }
if ((Read-ImageByte -Bytes $bytes -Lba $secondaryToolSlotPhysicalLba -Offset 0) -ne $secondaryToolSlotSeed) { throw 'Secondary tool slot seed mismatch after i386 probe.' }
if ((Read-ImageU32LE -Bytes $bytes -Lba $filesystemSuperblockPhysicalLba) -ne $filesystemMagic) { throw 'Filesystem magic mismatch after i386 probe.' }
if ((Read-ImageU32LE -Bytes $bytes -Lba $partitionStartLba) -ne $toolLayoutMagic) { throw 'Tool layout magic mismatch after i386 probe.' }

Write-Output 'BAREMETAL_I386_QEMU_AVAILABLE=True'
Write-Output "BAREMETAL_I386_QEMU_BINARY=$qemu"
Write-Output 'BAREMETAL_I386_QEMU_ATA_STORAGE_PROBE=pass'
Write-Output ("BAREMETAL_I386_QEMU_ATA_STORAGE_PROBE_CODE=0x{0:X2}" -f $expectedProbeCode)
Write-Output "BAREMETAL_I386_QEMU_ATA_STORAGE_STDOUT=$stdoutPath"
Write-Output "BAREMETAL_I386_QEMU_ATA_STORAGE_STDERR=$stderrPath"
