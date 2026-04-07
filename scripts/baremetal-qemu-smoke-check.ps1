# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 20
)

$ErrorActionPreference = "Stop"

$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$releaseDir = Join-Path $repo "release"

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
        "qemu-system-x86_64",
        "qemu-system-x86_64.exe",
        "C:\Program Files\qemu\qemu-system-x86_64.exe"
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

function Read-TaskResultOrEmpty {
    param([System.Threading.Tasks.Task[string]] $Task)
    try {
        return $Task.GetAwaiter().GetResult()
    } catch {
        return ""
    }
}

function Write-QemuLogs {
    param(
        [string] $Stdout,
        [string] $Stderr,
        [string] $StdoutPath,
        [string] $StderrPath
    )
    Set-Content -Path $StdoutPath -Value $Stdout -Encoding Ascii
    Set-Content -Path $StderrPath -Value $Stderr -Encoding Ascii
}

function Get-LogTail {
    param([string] $Path)
    if (-not (Test-Path $Path)) {
        return ""
    }
    return (Get-Content -Path $Path -Tail 40 -ErrorAction SilentlyContinue) -join "`n"
}

function Invoke-PvhSmokeFallback {
    param(
        [string] $Reason,
        [string] $StdoutPath,
        [string] $StderrPath,
        [string] $Artifact
    )

    $pvhScript = Join-Path $PSScriptRoot "baremetal-qemu-smoke-pvh-check.ps1"
    if (-not (Test-Path $pvhScript)) {
        return $false
    }

    Write-Output "BAREMETAL_QEMU_SMOKE_FALLBACK=pvh"
    Write-Output "BAREMETAL_QEMU_SMOKE_FALLBACK_REASON=$Reason"
    Write-Output "BAREMETAL_QEMU_ARTIFACT=$Artifact"
    Write-Output "BAREMETAL_QEMU_STDOUT_LOG=$StdoutPath"
    Write-Output "BAREMETAL_QEMU_STDERR_LOG=$StderrPath"
    & $pvhScript -TimeoutSeconds $TimeoutSeconds
    return $true
}

Set-Location $repo
$scriptStem = [System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
$buildPrefix = Join-Path $repo ("zig-out\" + $scriptStem)
$env:ZIG_LOCAL_CACHE_DIR = Join-Path $repo (".zig-cache-" + $scriptStem)
$env:ZIG_GLOBAL_CACHE_DIR = Join-Path $repo (".zig-global-cache-" + $scriptStem)
New-Item -ItemType Directory -Force -Path $releaseDir | Out-Null
New-Item -ItemType Directory -Force -Path $buildPrefix | Out-Null
$zig = Resolve-ZigExecutable
$qemu = Resolve-QemuExecutable

if ($null -eq $qemu) {
    Write-Output "BAREMETAL_QEMU_AVAILABLE=False"
    Write-Output "BAREMETAL_QEMU_SMOKE=skipped"
    return
}

$expectedExitCode = 85 # isa-debug-exit returns (code << 1) | 1, where code=0x2A

if (-not $SkipBuild) {
    # Keep the QEMU smoke artifact on the non-crashing ReleaseFast path used for release packaging.
    & $zig build baremetal -Doptimize=ReleaseFast -Dbaremetal-qemu-smoke=true --prefix $buildPrefix --summary all
    if ($LASTEXITCODE -ne 0) {
        throw "zig build baremetal -Doptimize=ReleaseFast -Dbaremetal-qemu-smoke=true failed with exit code $LASTEXITCODE"
    }
}

$artifact = Join-Path $buildPrefix "bin\openclaw-zig-baremetal.elf"
if ($null -eq $artifact) {
    throw "Bare-metal artifact not found after build."
}
if (-not (Test-Path $artifact)) {
    throw "Bare-metal QEMU smoke artifact not found at expected path: $artifact"
}
$artifact = (Resolve-Path $artifact).Path

$stdoutPath = Join-Path $releaseDir "qemu-smoke-stdout.log"
$stderrPath = Join-Path $releaseDir "qemu-smoke-stderr.log"
if (Test-Path $stdoutPath) { Remove-Item -Force $stdoutPath }
if (Test-Path $stderrPath) { Remove-Item -Force $stderrPath }

$qemuArgs = @(
    "-kernel", $artifact,
    "-nographic",
    "-no-reboot",
    "-no-shutdown",
    "-serial", "none",
    "-monitor", "none",
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
    $null = $proc.WaitForExit()
    $stdout = Read-TaskResultOrEmpty $stdoutTask
    $stderr = Read-TaskResultOrEmpty $stderrTask
    Write-QemuLogs -Stdout $stdout -Stderr $stderr -StdoutPath $stdoutPath -StderrPath $stderrPath
    if (Invoke-PvhSmokeFallback -Reason "timeout" -StdoutPath $stdoutPath -StderrPath $stderrPath -Artifact $artifact) {
        return
    }
    $stderrTail = Get-LogTail $stderrPath
    throw "QEMU bare-metal smoke timed out after $TimeoutSeconds seconds.`n$stderrTail"
}

$proc.WaitForExit()
$stdout = Read-TaskResultOrEmpty $stdoutTask
$stderr = Read-TaskResultOrEmpty $stderrTask
Write-QemuLogs -Stdout $stdout -Stderr $stderr -StdoutPath $stdoutPath -StderrPath $stderrPath
$exitCode = $proc.ExitCode
if ($exitCode -ne $expectedExitCode) {
    $stderrTail = Get-LogTail $stderrPath
    if ($stderrTail -match "without PVH ELF Note") {
        if (Invoke-PvhSmokeFallback -Reason "missing-pvh-note" -StdoutPath $stdoutPath -StderrPath $stderrPath -Artifact $artifact) {
            return
        }
    }
    throw "QEMU bare-metal smoke failed: exit=$exitCode expected=$expectedExitCode`n$stderrTail"
}

Write-Output "BAREMETAL_QEMU_AVAILABLE=True"
Write-Output "BAREMETAL_QEMU_BINARY=$qemu"
Write-Output "BAREMETAL_QEMU_ARTIFACT=$artifact"
Write-Output "BAREMETAL_QEMU_STDOUT_LOG=$stdoutPath"
Write-Output "BAREMETAL_QEMU_STDERR_LOG=$stderrPath"
Write-Output "BAREMETAL_QEMU_EXPECTED_EXIT_CODE=$expectedExitCode"
Write-Output "BAREMETAL_QEMU_EXIT_CODE=$exitCode"
Write-Output "BAREMETAL_QEMU_SMOKE=pass"
