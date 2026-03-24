# SPDX-License-Identifier: GPL-2.0-only
param(
    [Parameter(Mandatory = $true)]
    [string] $BuildOption,
    [Parameter(Mandatory = $true)]
    [string] $ProbeTag,
    [Parameter(Mandatory = $true)]
    [string] $DeviceModel,
    [Parameter(Mandatory = $true)]
    [int] $ExpectedProbeCode,
    [switch] $UseDgramEcho,
    [switch] $UseUserNet,
    [switch] $UseDebugLog,
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 30
)

$ErrorActionPreference = 'Stop'

if (($UseDgramEcho -and $UseUserNet) -or (-not $UseDgramEcho -and -not $UseUserNet)) {
    throw 'Select exactly one network mode: -UseDgramEcho or -UseUserNet.'
}

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$releaseDir = Join-Path $repo 'release'
$expectedExitCode = ($ExpectedProbeCode * 2) + 1
$echoScript = Join-Path $repo 'scripts\qemu-e1000-dgram-echo.ps1'
$probeKey = ($ProbeTag.ToUpperInvariant() -replace '[^A-Z0-9]+', '_')

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
    Write-Output ("BAREMETAL_I386_QEMU_{0}=skipped" -f $probeKey)
    return
}

if (-not $SkipBuild) {
    & $zig build baremetal-i386 -Doptimize=ReleaseFast ("-D{0}=true" -f $BuildOption) --summary all
    if ($LASTEXITCODE -ne 0) { throw "zig build baremetal-i386 $BuildOption failed with exit code $LASTEXITCODE" }
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
if ($null -eq $artifact) { throw 'i386 bare-metal artifact not found after build.' }

$stdoutPath = Join-Path $releaseDir ("qemu-i386-{0}.stdout.log" -f $ProbeTag)
$stderrPath = Join-Path $releaseDir ("qemu-i386-{0}.stderr.log" -f $ProbeTag)
$echoStdoutPath = Join-Path $releaseDir ("qemu-i386-{0}-echo.stdout.log" -f $ProbeTag)
$echoStderrPath = Join-Path $releaseDir ("qemu-i386-{0}-echo.stderr.log" -f $ProbeTag)
$debugLogPath = Join-Path $releaseDir ("qemu-i386-{0}.debug.log" -f $ProbeTag)
if (Test-Path $stdoutPath) { Remove-Item -Force $stdoutPath }
if (Test-Path $stderrPath) { Remove-Item -Force $stderrPath }
if (Test-Path $echoStdoutPath) { Remove-Item -Force $echoStdoutPath }
if (Test-Path $echoStderrPath) { Remove-Item -Force $echoStderrPath }
if (Test-Path $debugLogPath) { Remove-Item -Force $debugLogPath }

$echoProc = $null
$echoStdoutTask = $null
$echoStderrTask = $null
$netArgs = @()
if ($UseDgramEcho) {
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

    $netArgs = @(
        '-netdev', "dgram,id=n0,local.type=inet,local.host=127.0.0.1,local.port=$guestPort,remote.type=inet,remote.host=127.0.0.1,remote.port=$echoPort",
        '-device', "$DeviceModel,netdev=n0"
    )
} else {
    $netArgs = @(
        '-netdev', 'user,id=n0,restrict=on',
        '-device', "$DeviceModel,netdev=n0"
    )
}

$qemuArgs = @(
    '-kernel', $artifact,
    '-nographic',
    '-no-reboot',
    '-no-shutdown',
    '-serial', 'none',
    '-monitor', 'none'
) + $netArgs
if ($UseDebugLog) {
    $qemuArgs += @('-debugcon', "file:$debugLogPath", '-global', 'isa-debugcon.iobase=0xe9')
}
$qemuArgs += @('-device', 'isa-debug-exit,iobase=0xf4,iosize=0x04')

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
    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    Set-Content -Path $stdoutPath -Value $stdout -Encoding ascii
    Set-Content -Path $stderrPath -Value $stderr -Encoding ascii
    if ($UseDebugLog -and (Test-Path $debugLogPath)) {
        $debugTail = (Get-Content $debugLogPath -Raw).Trim()
        if (-not [string]::IsNullOrWhiteSpace($debugTail)) {
            throw "QEMU i386 $ProbeTag timed out after $TimeoutSeconds seconds. Last debug stages: $debugTail"
        }
    }
    throw "QEMU i386 $ProbeTag timed out after $TimeoutSeconds seconds."
}
$proc.WaitForExit()
$stdout = $stdoutTask.GetAwaiter().GetResult()
$stderr = $stderrTask.GetAwaiter().GetResult()
Set-Content -Path $stdoutPath -Value $stdout -Encoding ascii
Set-Content -Path $stderrPath -Value $stderr -Encoding ascii

if ($echoProc) {
    if (-not $echoProc.WaitForExit(5000)) {
        try { $echoProc.Kill($true) } catch {}
        throw "QEMU i386 $ProbeTag echo helper did not exit cleanly."
    }
    $echoStdout = $echoStdoutTask.GetAwaiter().GetResult()
    $echoStderr = $echoStderrTask.GetAwaiter().GetResult()
    Set-Content -Path $echoStdoutPath -Value $echoStdout -Encoding ascii
    Set-Content -Path $echoStderrPath -Value $echoStderr -Encoding ascii
    if ($echoProc.ExitCode -ne 0) {
        throw "QEMU i386 $ProbeTag echo helper failed with exit code $($echoProc.ExitCode)"
    }
}

$exitCode = $proc.ExitCode
if ($exitCode -ne $expectedExitCode) {
    $probeCode = [int](($exitCode - 1) / 2)
    throw ("QEMU i386 {0} failed with exit code {1} (probe code 0x{2:X2})." -f $ProbeTag, $exitCode, $probeCode)
}

Write-Output 'BAREMETAL_I386_QEMU_AVAILABLE=True'
Write-Output "BAREMETAL_I386_QEMU_BINARY=$qemu"
Write-Output "BAREMETAL_I386_QEMU_ARTIFACT=$artifact"
Write-Output ("BAREMETAL_I386_QEMU_{0}=pass" -f $probeKey)
Write-Output ("BAREMETAL_I386_QEMU_{0}_CODE=0x{1:X2}" -f $probeKey, $ExpectedProbeCode)
Write-Output ("BAREMETAL_I386_QEMU_{0}_STDOUT={1}" -f $probeKey, $stdoutPath)
Write-Output ("BAREMETAL_I386_QEMU_{0}_STDERR={1}" -f $probeKey, $stderrPath)
if ($UseDgramEcho) {
    Write-Output ("BAREMETAL_I386_QEMU_{0}_ECHO_STDOUT={1}" -f $probeKey, $echoStdoutPath)
    Write-Output ("BAREMETAL_I386_QEMU_{0}_ECHO_STDERR={1}" -f $probeKey, $echoStderrPath)
}
if ($UseDebugLog) {
    Write-Output ("BAREMETAL_I386_QEMU_{0}_DEBUG={1}" -f $probeKey, $debugLogPath)
}
