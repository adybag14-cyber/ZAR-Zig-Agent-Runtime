# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 30
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$releaseDir = Join-Path $repo 'release'
$expectedProbeCode = 0x46
$expectedExitCode = ($expectedProbeCode * 2) + 1
$echoScript = Join-Path $repo 'scripts\qemu-e1000-dgram-echo.ps1'

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

function Get-FreeUdpPort {
    $listener = [System.Net.Sockets.UdpClient]::new(0)
    try { return ([System.Net.IPEndPoint] $listener.Client.LocalEndPoint).Port }
    finally { $listener.Close() }
}

Set-Location $repo
New-Item -ItemType Directory -Force -Path $releaseDir | Out-Null
$zig = Resolve-ZigExecutable
$qemu = Resolve-QemuExecutable
if ($null -eq $qemu) {
    Write-Output 'BAREMETAL_I386_QEMU_AVAILABLE=False'
    Write-Output 'BAREMETAL_I386_QEMU_E1000_ARP_PROBE=skipped'
    return
}

if (-not $SkipBuild) {
    & $zig build baremetal-i386 -Doptimize=ReleaseFast -Dbaremetal-e1000-arp-probe=true --summary all
    if ($LASTEXITCODE -ne 0) { throw "zig build baremetal-i386 e1000 arp probe failed with exit code $LASTEXITCODE" }
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
if ($null -eq $artifact) { throw 'i386 E1000 artifact not found after build.' }

$stdoutPath = Join-Path $releaseDir 'qemu-i386-e1000-arp-probe.stdout.log'
$stderrPath = Join-Path $releaseDir 'qemu-i386-e1000-arp-probe.stderr.log'
$echoStdoutPath = Join-Path $releaseDir 'qemu-i386-e1000-arp-echo.stdout.log'
$echoStderrPath = Join-Path $releaseDir 'qemu-i386-e1000-arp-echo.stderr.log'
if (Test-Path $stdoutPath) { Remove-Item -Force $stdoutPath }
if (Test-Path $stderrPath) { Remove-Item -Force $stderrPath }
if (Test-Path $echoStdoutPath) { Remove-Item -Force $echoStdoutPath }
if (Test-Path $echoStderrPath) { Remove-Item -Force $echoStderrPath }

$echoPort = Get-FreeUdpPort
$guestPort = Get-FreeUdpPort
if ($guestPort -eq $echoPort) { $guestPort = Get-FreeUdpPort }

$echoPsi = New-Object System.Diagnostics.ProcessStartInfo
$echoPsi.FileName = 'powershell.exe'
$echoPsi.UseShellExecute = $false
$echoPsi.RedirectStandardOutput = $true
$echoPsi.RedirectStandardError = $true
$echoPsi.Arguments = @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', ('"{0}"' -f $echoScript),
    '-ListenPort', $echoPort,
    '-ReplyPort', $guestPort,
    '-TimeoutSeconds', $TimeoutSeconds
) -join ' '
$echoProc = New-Object System.Diagnostics.Process
$echoProc.StartInfo = $echoPsi
[void]$echoProc.Start()
$echoStdoutTask = $echoProc.StandardOutput.ReadToEndAsync()
$echoStderrTask = $echoProc.StandardError.ReadToEndAsync()
Start-Sleep -Milliseconds 300

$qemuArgs = @(
    '-kernel', $artifact,
    '-nographic',
    '-no-reboot',
    '-no-shutdown',
    '-serial', 'none',
    '-monitor', 'none',
    '-netdev', "dgram,id=n0,local.type=inet,local.host=127.0.0.1,local.port=$guestPort,remote.type=inet,remote.host=127.0.0.1,remote.port=$echoPort",
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
    throw "QEMU i386 E1000 ARP probe timed out after $TimeoutSeconds seconds."
}
$proc.WaitForExit()
$stdout = $stdoutTask.GetAwaiter().GetResult()
$stderr = $stderrTask.GetAwaiter().GetResult()
Set-Content -Path $stdoutPath -Value $stdout -Encoding ascii
Set-Content -Path $stderrPath -Value $stderr -Encoding ascii
if (-not $echoProc.WaitForExit(5000)) {
    try { $echoProc.Kill($true) } catch {}
}
$echoStdout = $echoStdoutTask.GetAwaiter().GetResult()
$echoStderr = $echoStderrTask.GetAwaiter().GetResult()
Set-Content -Path $echoStdoutPath -Value $echoStdout -Encoding ascii
Set-Content -Path $echoStderrPath -Value $echoStderr -Encoding ascii
$exitCode = $proc.ExitCode
if ($exitCode -ne $expectedExitCode) { throw "QEMU i386 E1000 ARP probe failed: expected exit $expectedExitCode but saw $exitCode" }
if ($echoProc.ExitCode -gt 0) { throw "QEMU i386 E1000 ARP echo helper failed with exit code $($echoProc.ExitCode)" }

Write-Output 'BAREMETAL_I386_QEMU_AVAILABLE=True'
Write-Output "BAREMETAL_I386_QEMU_BINARY=$qemu"
Write-Output 'BAREMETAL_I386_QEMU_E1000_ARP_PROBE=pass'
Write-Output ("BAREMETAL_I386_QEMU_E1000_ARP_PROBE_CODE=0x{0:X2}" -f $expectedProbeCode)
Write-Output "BAREMETAL_I386_QEMU_E1000_ARP_STDOUT=$stdoutPath"
Write-Output "BAREMETAL_I386_QEMU_E1000_ARP_STDERR=$stderrPath"
Write-Output "BAREMETAL_I386_QEMU_E1000_ARP_ECHO_STDOUT=$echoStdoutPath"
Write-Output "BAREMETAL_I386_QEMU_E1000_ARP_ECHO_STDERR=$echoStderrPath"
