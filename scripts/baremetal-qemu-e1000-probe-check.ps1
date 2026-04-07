# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 30
)

$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$releaseDir = Join-Path $repo 'release'
$expectedProbeCode = 0x45
$expectedExitCode = ($expectedProbeCode * 2) + 1

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

function Resolve-CompilerRtArchive {
    $cacheRoot = Resolve-ZigGlobalCacheDir
    $objRoot = Join-Path $cacheRoot 'o'
    if (-not (Test-Path $objRoot)) {
        return $null
    }

    $candidate = Get-ChildItem -Path $objRoot -Recurse -Filter 'libcompiler_rt.a' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($null -ne $candidate) {
        return $candidate.FullName
    }

    return $null
}

Set-Location $repo
New-Item -ItemType Directory -Force -Path $releaseDir | Out-Null

$zig = Resolve-ZigExecutable
$qemu = Resolve-QemuExecutable
$clang = Resolve-ClangExecutable
$lld = Resolve-LldExecutable
$compilerRt = Resolve-CompilerRtArchive
$zigGlobalCacheDir = Resolve-ZigGlobalCacheDir
$zigLocalCacheDir = if ($env:ZIG_LOCAL_CACHE_DIR -and $env:ZIG_LOCAL_CACHE_DIR.Trim().Length -gt 0) { $env:ZIG_LOCAL_CACHE_DIR } else { Join-Path $repo '.zig-cache' }

if ($null -eq $qemu) {
    Write-Output 'BAREMETAL_QEMU_AVAILABLE=False'
    Write-Output 'BAREMETAL_QEMU_E1000_PROBE=skipped'
    return
}

if ($null -eq $clang -or $null -eq $lld -or $null -eq $compilerRt) {
    Write-Output 'BAREMETAL_QEMU_AVAILABLE=True'
    Write-Output "BAREMETAL_QEMU_BINARY=$qemu"
    Write-Output 'BAREMETAL_QEMU_PVH_TOOLCHAIN_AVAILABLE=False'
    if ($null -eq $clang) { Write-Output 'BAREMETAL_QEMU_PVH_MISSING=clang' }
    if ($null -eq $lld) { Write-Output 'BAREMETAL_QEMU_PVH_MISSING=lld' }
    if ($null -eq $compilerRt) { Write-Output 'BAREMETAL_QEMU_PVH_MISSING=libcompiler_rt.a' }
    Write-Output 'BAREMETAL_QEMU_E1000_PROBE=skipped'
    return
}

$optionsPath = Join-Path $releaseDir 'qemu-e1000-probe-options.zig'
$rootModulePath = (Join-Path $repo "src/baremetal_main.zig").Replace('\\', '/')
$optionsModulePath = $optionsPath.Replace('\\', '/')
$mainObj = Join-Path $releaseDir 'openclaw-zig-baremetal-main-e1000-probe.o'
$bootObj = Join-Path $releaseDir 'openclaw-zig-pvh-boot-e1000-probe.o'
$artifact = Join-Path $releaseDir 'openclaw-zig-baremetal-pvh-e1000-probe.elf'
$bootSource = Join-Path $repo 'scripts\baremetal\pvh_boot.S'
$linkerScript = Join-Path $repo 'scripts\baremetal\pvh_lld.ld'
$echoScript = Join-Path $repo 'scripts\qemu-e1000-dgram-echo.ps1'
$stdoutPath = Join-Path $releaseDir 'qemu-e1000-probe.stdout.log'
$stderrPath = Join-Path $releaseDir 'qemu-e1000-probe.stderr.log'
$echoStdoutPath = Join-Path $releaseDir 'qemu-e1000-echo.stdout.log'
$echoStderrPath = Join-Path $releaseDir 'qemu-e1000-echo.stderr.log'

function Get-FreeUdpPort {
    $listener = [System.Net.Sockets.UdpClient]::new(0)
    try {
        return ([System.Net.IPEndPoint] $listener.Client.LocalEndPoint).Port
    }
    finally {
        $listener.Close()
    }
}

if (-not $SkipBuild) {
    New-Item -ItemType Directory -Force -Path $zigGlobalCacheDir | Out-Null
    New-Item -ItemType Directory -Force -Path $zigLocalCacheDir | Out-Null
    @"
pub const qemu_smoke: bool = false;
pub const console_probe_banner: bool = false;
pub const framebuffer_probe_banner: bool = false;
pub const ata_storage_probe: bool = false;
pub const e1000_probe: bool = true;
pub const rtl8139_probe: bool = false;
"@ | Set-Content -Path $optionsPath -Encoding Ascii

    & $zig build-obj `
        -fno-strip `
        -fsingle-threaded `
        -ODebug `
        -target x86_64-freestanding-none `
        -mcpu baseline `
        --dep build_options `
        "-Mroot=$rootModulePath" `
        "-Mbuild_options=$optionsModulePath" `
        --cache-dir "$zigLocalCacheDir" `
        --global-cache-dir "$zigGlobalCacheDir" `
        --name 'openclaw-zig-baremetal-main-e1000-probe' `
        "-femit-bin=$mainObj"
    if ($LASTEXITCODE -ne 0) {
        throw "zig build-obj for E1000 probe failed with exit code $LASTEXITCODE"
    }

    & $clang -c -target x86_64-unknown-elf $bootSource -o $bootObj
    if ($LASTEXITCODE -ne 0) {
        throw "clang assemble for E1000 PVH shim failed with exit code $LASTEXITCODE"
    }

    & $lld -flavor gnu -m elf_x86_64 -o $artifact -T $linkerScript $mainObj $bootObj $compilerRt
    if ($LASTEXITCODE -ne 0) {
        throw "lld link for E1000 PVH artifact failed with exit code $LASTEXITCODE"
    }
}

if (-not (Test-Path $artifact)) {
    throw "E1000 probe artifact is missing: $artifact"
}

if (Test-Path $stdoutPath) { Remove-Item -Force $stdoutPath }
if (Test-Path $stderrPath) { Remove-Item -Force $stderrPath }
if (Test-Path $echoStdoutPath) { Remove-Item -Force $echoStdoutPath }
if (Test-Path $echoStderrPath) { Remove-Item -Force $echoStderrPath }

$echoPort = Get-FreeUdpPort
$guestPort = Get-FreeUdpPort
if ($guestPort -eq $echoPort) {
    $guestPort = Get-FreeUdpPort
}

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
    throw "QEMU E1000 probe timed out after $TimeoutSeconds seconds."
}

$proc.WaitForExit()
$stdout = $stdoutTask.GetAwaiter().GetResult()
$stderr = $stderrTask.GetAwaiter().GetResult()
Set-Content -Path $stdoutPath -Value $stdout -Encoding Ascii
Set-Content -Path $stderrPath -Value $stderr -Encoding Ascii

if (-not $echoProc.WaitForExit(5000)) {
    try { $echoProc.Kill($true) } catch {}
    throw 'QEMU E1000 echo helper did not exit cleanly.'
}

$echoStdout = $echoStdoutTask.GetAwaiter().GetResult()
$echoStderr = $echoStderrTask.GetAwaiter().GetResult()
Set-Content -Path $echoStdoutPath -Value $echoStdout -Encoding Ascii
Set-Content -Path $echoStderrPath -Value $echoStderr -Encoding Ascii

$actualExitCode = $proc.ExitCode
Write-Output 'BAREMETAL_QEMU_AVAILABLE=True'
Write-Output "BAREMETAL_QEMU_BINARY=$qemu"
Write-Output 'BAREMETAL_QEMU_PVH_TOOLCHAIN_AVAILABLE=True'
Write-Output "BAREMETAL_QEMU_EXPECTED_EXIT=$expectedExitCode"
Write-Output "BAREMETAL_QEMU_ACTUAL_EXIT=$actualExitCode"
Write-Output "BAREMETAL_QEMU_STDOUT=$stdoutPath"
Write-Output "BAREMETAL_QEMU_STDERR=$stderrPath"
Write-Output "BAREMETAL_QEMU_E1000_ECHO_STDOUT=$echoStdoutPath"
Write-Output "BAREMETAL_QEMU_E1000_ECHO_STDERR=$echoStderrPath"

if ($actualExitCode -ne $expectedExitCode) {
    if ($stdout) { Write-Output $stdout.TrimEnd() }
    if ($stderr) { Write-Output $stderr.TrimEnd() }
    if ($echoStdout) { Write-Output $echoStdout.TrimEnd() }
    if ($echoStderr) { Write-Output $echoStderr.TrimEnd() }
    throw "QEMU E1000 probe failed: expected exit $expectedExitCode but saw $actualExitCode"
}

if ($echoProc.ExitCode -ne 0) {
    if ($echoStdout) { Write-Output $echoStdout.TrimEnd() }
    if ($echoStderr) { Write-Output $echoStderr.TrimEnd() }
    throw "QEMU E1000 echo helper failed with exit code $($echoProc.ExitCode)"
}

Write-Output 'BAREMETAL_QEMU_E1000_PROBE=passed'
