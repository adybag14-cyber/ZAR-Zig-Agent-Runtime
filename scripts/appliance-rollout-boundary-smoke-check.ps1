param(
    [int] $Port = 8098,
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

function Require-Equal {
    param(
        [string] $Name,
        $Actual,
        $Expected
    )

    if ("$Actual" -ne "$Expected") {
        throw "$Name expected '$Expected', got '$Actual'"
    }
}

function Require-True {
    param(
        [string] $Name,
        $Actual
    )

    if (-not [bool]$Actual) {
        throw "$Name expected true"
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

$stdoutLog = Join-Path $repo "tmp_smoke_appliance_rollout_stdout.log"
$stderrLog = Join-Path $repo "tmp_smoke_appliance_rollout_stderr.log"
Remove-Item $stdoutLog, $stderrLog -ErrorAction SilentlyContinue

$previousHttpPort = $env:OPENCLAW_ZIG_HTTP_PORT
$previousStatePath = $env:OPENCLAW_ZIG_STATE_PATH
$previousAttestKey = $env:OPENCLAW_ZIG_BOOT_ATTEST_KEY

$env:OPENCLAW_ZIG_HTTP_PORT = "$Port"
$env:OPENCLAW_ZIG_STATE_PATH = "memory://appliance-rollout-boundary-smoke"
$env:OPENCLAW_ZIG_BOOT_ATTEST_KEY = "appliance-rollout-boundary-smoke-key"

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

    $planCanary = Invoke-Rpc -Url $rpcUrl -Id "rollout-plan-canary" -Method "update.plan" -Params @{ channel = "canary" }
    Require-Equal -Name "canary plan http" -Actual $planCanary.StatusCode -Expected 200
    Require-Equal -Name "canary plan channel" -Actual $planCanary.Json.result.selection.channel -Expected "canary"
    Require-Equal -Name "canary plan target version" -Actual $planCanary.Json.result.selection.targetVersion -Expected "v0.2.0-zig-canary"
    Require-Equal -Name "canary plan dist tag" -Actual $planCanary.Json.result.selection.npmDistTag -Expected "canary"
    $canaryEntry = @($planCanary.Json.result.channels | Where-Object { $_.id -eq "canary" })
    Require-True -Name "canary channel listed" -Actual ($canaryEntry.Count -ge 1)

    $bootPolicySet = Invoke-Rpc -Url $rpcUrl -Id "rollout-boot-policy-set" -Method "system.boot.policy.set" -Params @{
        policy = "signature-required"
        enforceUpdateGate = $true
        verificationMaxAgeMs = 300000
        requiredSigner = "sigstore"
    }
    Require-Equal -Name "boot gate enabled" -Actual $bootPolicySet.Json.result.secureBoot.enforceUpdateGate -Expected $true

    $bootVerifyFail = Invoke-Rpc -Url $rpcUrl -Id "rollout-boot-verify-fail" -Method "system.boot.verify" -Params @{
        measurement = "mismatch-a"
        expectedHash = "mismatch-b"
        signer = "sigstore"
    }
    Require-Equal -Name "boot verify fail verified" -Actual $bootVerifyFail.Json.result.verified -Expected $false

    $updateBlocked = Invoke-Rpc -Url $rpcUrl -Id "rollout-update-blocked" -Method "update.run" -Params @{ channel = "canary" }
    Require-Equal -Name "blocked canary ok" -Actual $updateBlocked.Json.result.ok -Expected $false
    Require-Equal -Name "blocked canary status" -Actual $updateBlocked.Json.result.status -Expected "failed"
    Require-Equal -Name "blocked canary gate flag" -Actual $updateBlocked.Json.result.blockedBySecureBoot -Expected $true
    Require-Equal -Name "blocked canary channel" -Actual $updateBlocked.Json.result.channel -Expected "canary"

    $bootVerifyOk = Invoke-Rpc -Url $rpcUrl -Id "rollout-boot-verify-ok" -Method "system.boot.verify" -Params @{
        measurement = "hash-canary"
        expectedHash = "hash-canary"
        signer = "sigstore"
    }
    Require-Equal -Name "boot verify ok verified" -Actual $bootVerifyOk.Json.result.verified -Expected $true
    Require-Equal -Name "boot verify ok gate allowed" -Actual $bootVerifyOk.Json.result.updateGate.allowed -Expected $true

    $updateCanary = Invoke-Rpc -Url $rpcUrl -Id "rollout-update-canary" -Method "update.run" -Params @{
        channel = "canary"
        force = $true
    }
    Require-Equal -Name "canary update ok" -Actual $updateCanary.Json.result.ok -Expected $true
    Require-Equal -Name "canary update status" -Actual $updateCanary.Json.result.status -Expected "completed"
    Require-Equal -Name "canary update channel" -Actual $updateCanary.Json.result.channel -Expected "canary"
    Require-Equal -Name "canary update target" -Actual $updateCanary.Json.result.targetVersion -Expected "v0.2.0-zig-canary"
    Require-Equal -Name "canary update dist tag" -Actual $updateCanary.Json.result.npmDistTag -Expected "canary"

    $statusCanary = Invoke-Rpc -Url $rpcUrl -Id "rollout-status-canary" -Method "update.status" -Params @{ limit = 10 }
    Require-Equal -Name "status canary current channel" -Actual $statusCanary.Json.result.currentChannel -Expected "canary"
    Require-Equal -Name "status canary current version" -Actual $statusCanary.Json.result.currentVersion -Expected "v0.2.0-zig-canary"
    Require-Equal -Name "status canary dist tag" -Actual $statusCanary.Json.result.npm.distTag -Expected "canary"

    $planStable = Invoke-Rpc -Url $rpcUrl -Id "rollout-plan-stable" -Method "update.plan" -Params @{ channel = "stable" }
    Require-Equal -Name "stable plan channel" -Actual $planStable.Json.result.selection.channel -Expected "stable"
    Require-Equal -Name "stable plan target" -Actual $planStable.Json.result.selection.targetVersion -Expected "v0.2.0-zig-stable"
    Require-Equal -Name "stable plan dist tag" -Actual $planStable.Json.result.selection.npmDistTag -Expected "latest"

    $updateStable = Invoke-Rpc -Url $rpcUrl -Id "rollout-update-stable" -Method "update.run" -Params @{
        channel = "stable"
        force = $true
    }
    Require-Equal -Name "stable update ok" -Actual $updateStable.Json.result.ok -Expected $true
    Require-Equal -Name "stable update status" -Actual $updateStable.Json.result.status -Expected "completed"
    Require-Equal -Name "stable update channel" -Actual $updateStable.Json.result.channel -Expected "stable"
    Require-Equal -Name "stable update target" -Actual $updateStable.Json.result.targetVersion -Expected "v0.2.0-zig-stable"
    Require-Equal -Name "stable update dist tag" -Actual $updateStable.Json.result.npmDistTag -Expected "latest"

    $statusStable = Invoke-Rpc -Url $rpcUrl -Id "rollout-status-stable" -Method "update.status" -Params @{ limit = 10 }
    Require-Equal -Name "status stable current channel" -Actual $statusStable.Json.result.currentChannel -Expected "stable"
    Require-Equal -Name "status stable current version" -Actual $statusStable.Json.result.currentVersion -Expected "v0.2.0-zig-stable"
    Require-Equal -Name "status stable dist tag" -Actual $statusStable.Json.result.npm.distTag -Expected "latest"

    Write-Output "APPLIANCE_ROLLOUT_CANARY_PLAN_HTTP=$($planCanary.StatusCode)"
    Write-Output "APPLIANCE_ROLLOUT_CANARY_TARGET=$($planCanary.Json.result.selection.targetVersion)"
    Write-Output "APPLIANCE_ROLLOUT_BLOCKED_STATUS=$($updateBlocked.Json.result.status)"
    Write-Output "APPLIANCE_ROLLOUT_CANARY_STATUS=$($updateCanary.Json.result.status)"
    Write-Output "APPLIANCE_ROLLOUT_CANARY_CHANNEL=$($statusCanary.Json.result.currentChannel)"
    Write-Output "APPLIANCE_ROLLOUT_STABLE_STATUS=$($updateStable.Json.result.status)"
    Write-Output "APPLIANCE_ROLLOUT_STABLE_CHANNEL=$($statusStable.Json.result.currentChannel)"
}
finally {
    if ($null -ne $proc -and -not $proc.HasExited) {
        Stop-Process -Id $proc.Id -Force
    }

    if ($null -eq $previousHttpPort) {
        Remove-Item Env:OPENCLAW_ZIG_HTTP_PORT -ErrorAction SilentlyContinue
    } else {
        $env:OPENCLAW_ZIG_HTTP_PORT = $previousHttpPort
    }

    if ($null -eq $previousStatePath) {
        Remove-Item Env:OPENCLAW_ZIG_STATE_PATH -ErrorAction SilentlyContinue
    } else {
        $env:OPENCLAW_ZIG_STATE_PATH = $previousStatePath
    }

    if ($null -eq $previousAttestKey) {
        Remove-Item Env:OPENCLAW_ZIG_BOOT_ATTEST_KEY -ErrorAction SilentlyContinue
    } else {
        $env:OPENCLAW_ZIG_BOOT_ATTEST_KEY = $previousAttestKey
    }

    if (-not $KeepLogs) {
        Remove-Item $stdoutLog, $stderrLog -ErrorAction SilentlyContinue
    }
}
