# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 30,
    [int] $DiskSizeMiB = 8
)

$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$releaseDir = Join-Path $repo 'release'
$expectedProbeCode = 0x57
$expectedExitCode = ($expectedProbeCode * 2) + 1
$serverScript = Join-Path $repo 'scripts\qemu-rtl8139-https-post-server.ps1'

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
    Write-Output 'BAREMETAL_I386_QEMU_VIRTIO_NET_HTTPS_POST_PROBE=skipped'
    return
}
if (-not (Test-Path $serverScript)) { throw "HTTPS probe server script is missing: $serverScript" }

if (-not $SkipBuild) {
    & $zig build baremetal-i386 -Doptimize=ReleaseFast -Dbaremetal-virtio-net-https-post-probe=true --summary all
    if ($LASTEXITCODE -ne 0) { throw "zig build baremetal-i386 e1000 https post probe failed with exit code $LASTEXITCODE" }
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
if ($null -eq $artifact) { throw 'i386 VIRTIO-NET HTTPS POST artifact not found after build.' }

$diskImage = Join-Path $releaseDir 'qemu-i386-virtio-net-https-post-probe.img'
$serverReadyPath = Join-Path $releaseDir 'qemu-i386-virtio-net-https-post-server.ready'
$serverStatusPath = Join-Path $releaseDir 'qemu-i386-virtio-net-https-post-server.status.txt'
$serverRequestLogPath = Join-Path $releaseDir 'qemu-i386-virtio-net-https-post-server.request.log'
$serverStdoutPath = Join-Path $releaseDir 'qemu-i386-virtio-net-https-post-server.stdout.log'
$serverStderrPath = Join-Path $releaseDir 'qemu-i386-virtio-net-https-post-server.stderr.log'
$pcapPath = Join-Path $releaseDir 'qemu-i386-virtio-net-https-post-probe.pcap'
$stdoutPath = Join-Path $releaseDir 'qemu-i386-virtio-net-https-post-probe.stdout.log'
$stderrPath = Join-Path $releaseDir 'qemu-i386-virtio-net-https-post-probe.stderr.log'
New-RawDiskImage -Path $diskImage -SizeMiB $DiskSizeMiB
foreach ($path in @($serverReadyPath, $serverStatusPath, $serverRequestLogPath, $serverStdoutPath, $serverStderrPath, $pcapPath, $stdoutPath, $stderrPath)) {
    if (Test-Path $path) { Remove-Item -Force $path }
}

$serverProc = $null
try {
    $serverProc = Start-Process powershell -ArgumentList @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $serverScript,
        '-Port', '8443',
        '-ReadyPath', $serverReadyPath,
        '-StatusPath', $serverStatusPath,
        '-RequestLogPath', $serverRequestLogPath
    ) -PassThru -RedirectStandardOutput $serverStdoutPath -RedirectStandardError $serverStderrPath

    $readyDeadline = [DateTime]::UtcNow.AddSeconds(10)
    while (-not (Test-Path $serverReadyPath)) {
        if ($serverProc.HasExited) {
            $statusText = if (Test-Path $serverStatusPath) { Get-Content $serverStatusPath -Raw } else { '<missing status>' }
            throw "E1000 HTTPS probe server exited before ready: $statusText"
        }
        if ([DateTime]::UtcNow -ge $readyDeadline) { throw 'Timed out waiting for HTTPS probe server readiness.' }
        Start-Sleep -Milliseconds 100
    }

    $qemuArgs = @(
        '-kernel', $artifact,
        '-drive', "file=$diskImage,if=ide,format=raw,index=0,media=disk",
        '-nographic',
        '-no-reboot',
        '-no-shutdown',
        '-serial', 'none',
        '-monitor', 'none',
        '-netdev', 'user,id=n0,restrict=off',
        '-device', 'virtio-net-pci,netdev=n0,disable-legacy=on',
        '-object', "filter-dump,id=f1,netdev=n0,file=$pcapPath",
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
        throw "QEMU i386 VIRTIO-NET HTTPS POST probe timed out after $TimeoutSeconds seconds."
    }
    $proc.WaitForExit()
    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    Set-Content -Path $stdoutPath -Value $stdout -Encoding ascii
    Set-Content -Path $stderrPath -Value $stderr -Encoding ascii
    $exitCode = $proc.ExitCode
    if ($exitCode -ne $expectedExitCode) {
        $probeCode = [int](($exitCode - 1) / 2)
        throw ("QEMU i386 VIRTIO-NET HTTPS POST probe failed with exit code {0} (probe code 0x{1:X2})." -f $exitCode, $probeCode)
    }

    $serverExitDeadline = [DateTime]::UtcNow.AddSeconds(3)
    while (-not $serverProc.HasExited -and [DateTime]::UtcNow -lt $serverExitDeadline) {
        Start-Sleep -Milliseconds 100
    }
    if (-not $serverProc.HasExited) {
        $serverProc.Kill()
        $serverProc.WaitForExit()
    }

    $serverStatusText = if (Test-Path $serverStatusPath) { (Get-Content $serverStatusPath -Raw).Trim() } else { '' }
    if ($serverStatusText -ne 'ok') { throw "E1000 HTTPS probe server did not finish cleanly: $serverStatusText" }
    if (-not (Test-Path $serverRequestLogPath)) { throw 'E1000 HTTPS probe server did not capture the request log.' }
}
finally {
    if ($null -ne $serverProc -and -not $serverProc.HasExited) {
        try { $serverProc.Kill() } catch {}
        try { $serverProc.WaitForExit() } catch {}
    }
}

Write-Output 'BAREMETAL_I386_QEMU_AVAILABLE=True'
Write-Output "BAREMETAL_I386_QEMU_BINARY=$qemu"
Write-Output 'BAREMETAL_I386_QEMU_VIRTIO_NET_HTTPS_POST_PROBE=pass'
Write-Output ("BAREMETAL_I386_QEMU_VIRTIO_NET_HTTPS_POST_PROBE_CODE=0x{0:X2}" -f $expectedProbeCode)
Write-Output "BAREMETAL_I386_QEMU_VIRTIO_NET_HTTPS_POST_STDOUT=$stdoutPath"
Write-Output "BAREMETAL_I386_QEMU_VIRTIO_NET_HTTPS_POST_STDERR=$stderrPath"
Write-Output "BAREMETAL_I386_QEMU_VIRTIO_NET_HTTPS_POST_SERVER_STATUS=$serverStatusPath"
Write-Output "BAREMETAL_I386_QEMU_VIRTIO_NET_HTTPS_POST_REQUEST_LOG=$serverRequestLogPath"
Write-Output "BAREMETAL_I386_QEMU_VIRTIO_NET_HTTPS_POST_PCAP=$pcapPath"

