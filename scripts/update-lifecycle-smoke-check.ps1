param(
    [int] $Port = 8095,
    [int] $ReadyAttempts = 80,
    [int] $ReadySleepMs = 500,
    [switch] $SkipBuild,
    [switch] $KeepLogs
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

function Resolve-AgentExecutable {
    param([string] $RepoPath)

    $candidates = @(
        (Join-Path $RepoPath "zig-out\bin\openclaw-zig.exe"),
        (Join-Path $RepoPath "zig-out/bin/openclaw-zig.exe"),
        (Join-Path $RepoPath "zig-out\bin\openclaw-zig"),
        (Join-Path $RepoPath "zig-out/bin/openclaw-zig")
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return (Resolve-Path $candidate).Path
        }
    }

    throw "openclaw-zig executable not found under zig-out/bin."
}

function Invoke-Rpc {
    param(
        [string] $Url,
        [string] $Id,
        [string] $Method,
        [hashtable] $Params
    )

    $payload = @{
        id = $Id
        method = $Method
        params = if ($null -eq $Params) { @{} } else { $Params }
    } | ConvertTo-Json -Depth 12 -Compress

    $resp = Invoke-WebRequest -Uri $Url -Method Post -ContentType "application/json" -Body $payload -UseBasicParsing
    $json = $resp.Content | ConvertFrom-Json
    if ($null -ne $json.error) {
        throw "RPC $Method returned error: $($json.error | ConvertTo-Json -Depth 8 -Compress)"
    }
    return @{
        StatusCode = $resp.StatusCode
        Json = $json
        Content = $resp.Content
    }
}

$zig = Resolve-ZigExecutable
if (-not $SkipBuild) {
    & $zig build --summary all
    if ($LASTEXITCODE -ne 0) {
        throw "zig build failed with exit code $LASTEXITCODE"
    }
}

$exe = Resolve-AgentExecutable -RepoPath $repo

$env:OPENCLAW_ZIG_HTTP_PORT = "$Port"
$stdoutLog = Join-Path $repo "tmp_smoke_update_stdout.log"
$stderrLog = Join-Path $repo "tmp_smoke_update_stderr.log"
Remove-Item $stdoutLog, $stderrLog -ErrorAction SilentlyContinue

$proc = Start-Process -FilePath $exe -ArgumentList @("--serve") -WorkingDirectory $repo -PassThru -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog
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
    $rpcUrl = "$baseUrl/rpc"

    $planStable = Invoke-Rpc -Url $rpcUrl -Id "upd-plan-stable" -Method "update.plan" -Params @{ channel = "stable" }
    $planEdge = Invoke-Rpc -Url $rpcUrl -Id "upd-plan-edge" -Method "update.plan" -Params @{ channel = "edge" }

    if (-not $planStable.Json.result.selection.targetVersion) {
        throw "update.plan (stable) missing selection.targetVersion"
    }
    if (-not $planEdge.Json.result.selection.targetVersion) {
        throw "update.plan (edge) missing selection.targetVersion"
    }

    $runDry = Invoke-Rpc -Url $rpcUrl -Id "upd-run-dry" -Method "update.run" -Params @{
        channel = "stable"
        dryRun = $true
    }
    if ("$($runDry.Json.result.status)" -ne "completed") {
        throw "update.run dry-run did not complete"
    }

    $runApply = Invoke-Rpc -Url $rpcUrl -Id "upd-run-apply" -Method "update.run" -Params @{
        targetVersion = "edge"
        dryRun = $false
        force = $false
    }
    if ("$($runApply.Json.result.status)" -ne "completed") {
        throw "update.run apply did not complete"
    }

    $status = Invoke-Rpc -Url $rpcUrl -Id "upd-status" -Method "update.status" -Params @{ limit = 10 }
    $statusTotal = [int]$status.Json.result.counts.total
    if ($statusTotal -lt 2) {
        throw "update.status expected at least 2 jobs, got $statusTotal"
    }
    if (-not $status.Json.result.latestRun) {
        throw "update.status missing latestRun"
    }

    Write-Output "UPDATE_PLAN_STABLE_HTTP=$($planStable.StatusCode)"
    Write-Output "UPDATE_PLAN_EDGE_HTTP=$($planEdge.StatusCode)"
    Write-Output "UPDATE_RUN_DRY_HTTP=$($runDry.StatusCode)"
    Write-Output "UPDATE_RUN_APPLY_HTTP=$($runApply.StatusCode)"
    Write-Output "UPDATE_STATUS_HTTP=$($status.StatusCode)"
    Write-Output "UPDATE_CURRENT_VERSION=$($status.Json.result.currentVersion)"
    Write-Output "UPDATE_CURRENT_CHANNEL=$($status.Json.result.currentChannel)"
    Write-Output "UPDATE_JOBS_TOTAL=$statusTotal"
}
finally {
    if ($null -ne $proc -and -not $proc.HasExited) {
        Stop-Process -Id $proc.Id -Force
    }
    Remove-Item Env:OPENCLAW_ZIG_HTTP_PORT -ErrorAction SilentlyContinue
    if (-not $KeepLogs) {
        Remove-Item $stdoutLog, $stderrLog -ErrorAction SilentlyContinue
    }
}
