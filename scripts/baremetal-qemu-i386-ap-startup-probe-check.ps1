# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 60
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

function Resolve-ZigExecutable {
    $defaultWindowsZig = "C:\Users\Ady\Documents\toolchains\zig-master\current\zig.exe"
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

    throw "Zig executable not found. Set OPENCLAW_ZIG_BIN or ensure `zig` is on PATH."
}

function Resolve-QemuExecutable {
    $candidates = @(
        "qemu-system-i386",
        "qemu-system-i386.exe",
        "C:\Program Files\qemu\qemu-system-i386.exe"
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

Set-Location $repo
$scriptStem = [System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
$buildPrefix = Join-Path $repo ("zig-out\" + $scriptStem)
$env:ZIG_LOCAL_CACHE_DIR = Join-Path $repo (".zig-cache-" + $scriptStem)
$env:ZIG_GLOBAL_CACHE_DIR = Join-Path $repo (".zig-global-cache-" + $scriptStem)
New-Item -ItemType Directory -Force -Path $buildPrefix | Out-Null
$zig = Resolve-ZigExecutable
$qemu = Resolve-QemuExecutable

if ($null -eq $qemu) {
    Write-Output "BAREMETAL_I386_QEMU_AVAILABLE=False"
    Write-Output "BAREMETAL_I386_QEMU_AP_STARTUP_PROBE=skipped"
    return
}

$fallbackProbeCode = 0x7E
$executionProbeCode = 0x7F
$expectedExitCodes = @{
    (($fallbackProbeCode * 2) + 1) = $fallbackProbeCode
    (($executionProbeCode * 2) + 1) = $executionProbeCode
}

if (-not $SkipBuild) {
    & $zig build baremetal-i386 -Doptimize=ReleaseFast -Dbaremetal-i386-ap-startup-probe=true --prefix $buildPrefix --summary all
    if ($LASTEXITCODE -ne 0) {
        throw "zig build baremetal-i386 -Dbaremetal-i386-ap-startup-probe=true failed with exit code $LASTEXITCODE"
    }
}

$artifactCandidates = @(
    (Join-Path $buildPrefix "bin\openclaw-zig-baremetal-i386.elf"),
    (Join-Path $repo "zig-out\bin\openclaw-zig-baremetal-i386.elf"),
    (Join-Path $repo "zig-out/openclaw-zig-baremetal-i386.elf"),
    (Join-Path $repo "zig-out\openclaw-zig-baremetal-i386.elf")
)

$artifact = $null
foreach ($candidate in $artifactCandidates) {
    if (Test-Path $candidate) {
        $artifact = (Resolve-Path $candidate).Path
        break
    }
}
if ($null -eq $artifact) {
    throw "i386 bare-metal AP startup artifact not found after build."
}

$stdoutPath = Join-Path $repo "release\qemu-i386-ap-startup-probe-stdout.log"
$stderrPath = Join-Path $repo "release\qemu-i386-ap-startup-probe-stderr.log"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $stdoutPath) | Out-Null
if (Test-Path $stdoutPath) { Remove-Item -Force $stdoutPath }
if (Test-Path $stderrPath) { Remove-Item -Force $stderrPath }

$qemuArgs = @(
    "-M", "q35,accel=tcg",
    "-m", "128M",
    "-smp", "2",
    "-kernel", $artifact,
    "-display", "none",
    "-serial", "none",
    "-monitor", "none",
    "-no-reboot",
    "-no-shutdown",
    "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04"
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
    throw "QEMU i386 AP startup probe timed out after $TimeoutSeconds seconds."
}

$proc.WaitForExit()
$stdout = $stdoutTask.GetAwaiter().GetResult()
$stderr = $stderrTask.GetAwaiter().GetResult()
Set-Content -Path $stdoutPath -Value $stdout -Encoding Ascii
Set-Content -Path $stderrPath -Value $stderr -Encoding Ascii
$exitCode = $proc.ExitCode
if (-not $expectedExitCodes.ContainsKey($exitCode)) {
    $stderrTail = ""
    if (Test-Path $stderrPath) {
        $stderrTail = (Get-Content -Path $stderrPath -Tail 40 -ErrorAction SilentlyContinue) -join "`n"
    }
    $expectedText = ($expectedExitCodes.Keys | Sort-Object) -join ", "
    throw "QEMU i386 AP startup probe failed: exit=$exitCode expected one of [$expectedText]`n$stderrTail"
}

$observedProbeCode = [int]$expectedExitCodes[$exitCode]
$executionObserved = ($observedProbeCode -eq $executionProbeCode)

Write-Output "BAREMETAL_I386_QEMU_AVAILABLE=True"
Write-Output "BAREMETAL_I386_QEMU_BINARY=$qemu"
Write-Output "BAREMETAL_I386_QEMU_ARTIFACT=$artifact"
Write-Output ("BAREMETAL_I386_QEMU_EXPECTED_EXIT_CODES={0}" -f (($expectedExitCodes.Keys | Sort-Object) -join ","))
Write-Output "BAREMETAL_I386_QEMU_EXIT_CODE=$exitCode"
Write-Output ("BAREMETAL_I386_QEMU_AP_STARTUP_PROBE_CODE=0x{0:X2}" -f $observedProbeCode)
Write-Output ("BAREMETAL_I386_QEMU_AP_EXECUTION_OBSERVED={0}" -f ($(if ($executionObserved) { "True" } else { "False" })))
Write-Output "BAREMETAL_I386_QEMU_AP_STARTUP_PROBE=pass"
