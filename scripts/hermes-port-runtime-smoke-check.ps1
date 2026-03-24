# SPDX-License-Identifier: GPL-2.0-only
param(
    [int] $Port = 18084,
    [int] $ReadyAttempts = 80,
    [int] $ReadySleepMs = 500,
    [switch] $SkipBuild,
    [switch] $KeepLogs
)

$ErrorActionPreference = "Stop"

$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$smokeScript = Join-Path $repo "scripts/hermes-port-rpc-smoke.mjs"

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

function Resolve-NodeExecutable {
    if ($env:OPENCLAW_NODE_BIN -and $env:OPENCLAW_NODE_BIN.Trim().Length -gt 0) {
        if (-not (Test-Path $env:OPENCLAW_NODE_BIN)) {
            throw "OPENCLAW_NODE_BIN is set but not found: $($env:OPENCLAW_NODE_BIN)"
        }
        return $env:OPENCLAW_NODE_BIN
    }

    $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
    if ($null -ne $nodeCmd -and $nodeCmd.Path) {
        return $nodeCmd.Path
    }

    throw "Node executable not found. Set OPENCLAW_NODE_BIN or ensure `node` is on PATH."
}

function Resolve-AgentLaunchSpec {
    param(
        [string] $RepoPath,
        [string] $ZigPath
    )

    $isWindowsHost = $env:OS -eq "Windows_NT"
    $candidates = if ($isWindowsHost) {
        @(
            (Join-Path $RepoPath "zig-out\\bin\\openclaw-zig.exe"),
            (Join-Path $RepoPath "zig-out/bin/openclaw-zig.exe")
        )
    } else {
        @(
            (Join-Path $RepoPath "zig-out\\bin\\openclaw-zig"),
            (Join-Path $RepoPath "zig-out/bin/openclaw-zig"),
            (Join-Path $RepoPath "zig-out\\bin\\openclaw-zig.exe"),
            (Join-Path $RepoPath "zig-out/bin/openclaw-zig.exe")
        )
    }

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return @{
                FilePath = (Resolve-Path $candidate).Path
                Arguments = @("--serve")
                Mode = "binary"
            }
        }
    }

    if ($isWindowsHost) {
        return @{
            FilePath = $ZigPath
            Arguments = @("build", "run", "--", "--serve")
            Mode = "zig-build-run"
        }
    }

    throw "openclaw-zig executable not found under zig-out/bin."
}

$zig = Resolve-ZigExecutable
$node = Resolve-NodeExecutable

if (-not $SkipBuild) {
    & $zig build --summary all
    if ($LASTEXITCODE -ne 0) {
        throw "zig build failed with exit code $LASTEXITCODE"
    }
}

$launch = Resolve-AgentLaunchSpec -RepoPath $repo -ZigPath $zig

$stateRoot = Join-Path $repo "tmp_hermes_port_state"
$workRoot = Join-Path $repo "tmp_hermes_port_work"
$stdoutLog = Join-Path $repo "tmp_hermes_port_stdout.log"
$stderrLog = Join-Path $repo "tmp_hermes_port_stderr.log"

Remove-Item $stdoutLog, $stderrLog -ErrorAction SilentlyContinue
Remove-Item $stateRoot, $workRoot -Recurse -Force -ErrorAction SilentlyContinue

$env:OPENCLAW_ZIG_HTTP_PORT = "$Port"
$env:OPENCLAW_ZIG_STATE_PATH = $stateRoot

$proc = Start-Process -FilePath $launch.FilePath -ArgumentList $launch.Arguments -WorkingDirectory $repo -PassThru -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog
$baseUrl = "http://127.0.0.1:$Port"

$ready = $false
for ($i = 0; $i -lt $ReadyAttempts; $i++) {
    if ($proc.HasExited) { break }
    try {
        $health = Invoke-WebRequest -Uri "$baseUrl/health" -UseBasicParsing -TimeoutSec 2
        if ($health.StatusCode -eq 200) {
            $ready = $true
            break
        }
    } catch {
        Start-Sleep -Milliseconds $ReadySleepMs
    }
}

if (-not $ready) {
    $stderrTail = if (Test-Path $stderrLog) { (Get-Content $stderrLog -Tail 120 -ErrorAction SilentlyContinue) -join "`n" } else { "" }
    $stdoutTail = if (Test-Path $stdoutLog) { (Get-Content $stdoutLog -Tail 80 -ErrorAction SilentlyContinue) -join "`n" } else { "" }
    $exitCode = if ($proc.HasExited) { $proc.ExitCode } else { "running" }
    throw "openclaw-zig did not become ready on $baseUrl (exit=$exitCode)`nSTDERR:`n$stderrTail`nSTDOUT:`n$stdoutTail"
}

try {
    New-Item -ItemType Directory -Path $workRoot -Force | Out-Null
    $env:ZAR_RPC_URL = "$baseUrl/rpc"
    $env:ZAR_ZIG_BIN = $zig
    $env:ZAR_SMOKE_ROOT = $workRoot
    $env:ZAR_SMOKE_SESSION_ID = "hermes-port-smoke"

    & $node $smokeScript
    if ($LASTEXITCODE -ne 0) {
        throw "hermes-port-rpc-smoke.mjs failed with exit code $LASTEXITCODE"
    }

    Write-Output "SMOKE_HERMES_RPC_URL=$($env:ZAR_RPC_URL)"
    Write-Output "SMOKE_HERMES_ZIG=$zig"
    Write-Output "SMOKE_HERMES_NODE=$node"
    Write-Output "SMOKE_HERMES_LAUNCH_MODE=$($launch.Mode)"
    Write-Output "SMOKE_HERMES_WORK_ROOT=$workRoot"
}
finally {
    if ($null -ne $proc -and -not $proc.HasExited) {
        Stop-Process -Id $proc.Id -Force
    }

    Remove-Item Env:OPENCLAW_ZIG_HTTP_PORT -ErrorAction SilentlyContinue
    Remove-Item Env:OPENCLAW_ZIG_STATE_PATH -ErrorAction SilentlyContinue
    Remove-Item Env:ZAR_RPC_URL -ErrorAction SilentlyContinue
    Remove-Item Env:ZAR_ZIG_BIN -ErrorAction SilentlyContinue
    Remove-Item Env:ZAR_SMOKE_ROOT -ErrorAction SilentlyContinue
    Remove-Item Env:ZAR_SMOKE_SESSION_ID -ErrorAction SilentlyContinue

    if (-not $KeepLogs) {
        Remove-Item $stdoutLog, $stderrLog -ErrorAction SilentlyContinue
        Remove-Item $stateRoot, $workRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
