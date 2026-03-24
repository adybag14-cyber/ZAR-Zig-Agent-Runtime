# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 30,
    [int] $DiskSizeMiB = 8
)

$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$releaseDir = Join-Path $repo 'release'
$expectedProbeCode = 0x4A
$expectedExitCode = ($expectedProbeCode * 2) + 1

function Resolve-ZigExecutable {
    $default = 'C:\Users\Ady\Documents\toolchains\zig-master\current\zig.exe'
    if ($env:OPENCLAW_ZIG_BIN -and $env:OPENCLAW_ZIG_BIN.Trim().Length -gt 0) {
        if (-not (Test-Path $env:OPENCLAW_ZIG_BIN)) { throw "OPENCLAW_ZIG_BIN is set but not found: $($env:OPENCLAW_ZIG_BIN)" }
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

function New-RawDiskImage {
    param([string] $Path, [int] $SizeMiB)
    if (Test-Path $Path) { Remove-Item -Force $Path }
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::ReadWrite)
    try { $stream.SetLength([int64]$SizeMiB * 1MB) } finally { $stream.Dispose() }
}

Set-Location $repo
New-Item -ItemType Directory -Force -Path $releaseDir | Out-Null
$zig = Resolve-ZigExecutable
$qemu = Resolve-QemuExecutable
if ($null -eq $qemu) {
    Write-Output 'BAREMETAL_I386_QEMU_AVAILABLE=False'
    Write-Output 'BAREMETAL_I386_QEMU_E1000_HTTP_POST_PROBE=skipped'
    return
}

if (-not $SkipBuild) {
    & $zig build baremetal-i386 -Doptimize=ReleaseFast -Dbaremetal-e1000-http-post-probe=true --summary all
    if ($LASTEXITCODE -ne 0) { throw "zig build baremetal-i386 e1000 http post probe failed with exit code $LASTEXITCODE" }
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
if ($null -eq $artifact) { throw 'i386 E1000 HTTP POST artifact not found after build.' }

$diskImage = Join-Path $releaseDir 'qemu-i386-e1000-http-post-probe.img'
$stdoutPath = Join-Path $releaseDir 'qemu-i386-e1000-http-post-probe.stdout.log'
$stderrPath = Join-Path $releaseDir 'qemu-i386-e1000-http-post-probe.stderr.log'
New-RawDiskImage -Path $diskImage -SizeMiB $DiskSizeMiB
if (Test-Path $stdoutPath) { Remove-Item -Force $stdoutPath }
if (Test-Path $stderrPath) { Remove-Item -Force $stderrPath }

$qemuArgs = @(
    '-kernel', $artifact,
    '-drive', "file=$diskImage,if=ide,format=raw,index=0,media=disk",
    '-nographic',
    '-no-reboot',
    '-no-shutdown',
    '-serial', 'none',
    '-monitor', 'none',
    '-netdev', 'user,id=n0,restrict=on',
    '-device', 'e1000,netdev=n0',
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
    throw "QEMU i386 E1000 HTTP POST probe timed out after $TimeoutSeconds seconds."
}
$proc.WaitForExit()
$stdout = $stdoutTask.GetAwaiter().GetResult()
$stderr = $stderrTask.GetAwaiter().GetResult()
Set-Content -Path $stdoutPath -Value $stdout -Encoding ascii
Set-Content -Path $stderrPath -Value $stderr -Encoding ascii
$exitCode = $proc.ExitCode
if ($exitCode -ne $expectedExitCode) {
    $probeCode = [int](($exitCode - 1) / 2)
    throw ("QEMU i386 E1000 HTTP POST probe failed with exit code {0} (probe code 0x{1:X2})." -f $exitCode, $probeCode)
}

Write-Output 'BAREMETAL_I386_QEMU_AVAILABLE=True'
Write-Output "BAREMETAL_I386_QEMU_BINARY=$qemu"
Write-Output 'BAREMETAL_I386_QEMU_E1000_HTTP_POST_PROBE=pass'
Write-Output ("BAREMETAL_I386_QEMU_E1000_HTTP_POST_PROBE_CODE=0x{0:X2}" -f $expectedProbeCode)
Write-Output "BAREMETAL_I386_QEMU_E1000_HTTP_POST_STDOUT=$stdoutPath"
Write-Output "BAREMETAL_I386_QEMU_E1000_HTTP_POST_STDERR=$stderrPath"
