# SPDX-License-Identifier: GPL-2.0-only
param(
    [int] $Port = 8094,
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
    } | ConvertTo-Json -Depth 10 -Compress

    $resp = Invoke-WebRequest -Uri $Url -Method Post -ContentType "application/json" -Body $payload -UseBasicParsing
    $json = $resp.Content | ConvertFrom-Json
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
$stdoutLog = Join-Path $repo "tmp_smoke_runtime_stdout.log"
$stderrLog = Join-Path $repo "tmp_smoke_runtime_stderr.log"
Remove-Item $stdoutLog,$stderrLog -ErrorAction SilentlyContinue

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
    $health = Invoke-WebRequest -Uri "$baseUrl/health" -UseBasicParsing
    $statusRpc = Invoke-Rpc -Url "$baseUrl/rpc" -Id "rt-status" -Method "status" -Params @{}
    $runtimeFile = Join-Path $repo 'tmp_runtime_rpc_smoke.txt'
    $runtimeCommand = if ($IsWindows -or $env:OS -eq 'Windows_NT') { 'echo runtime-smoke-exec' } else { 'printf runtime-smoke-exec' }

    $runtimeWrite = Invoke-Rpc -Url "$baseUrl/rpc" -Id "rt-file-write" -Method "file.write" -Params @{
        sessionId = "runtime-rpc-smoke"
        path = $runtimeFile
        content = "runtime-smoke-file"
    }
    $runtimeRead = Invoke-Rpc -Url "$baseUrl/rpc" -Id "rt-file-read" -Method "file.read" -Params @{
        sessionId = "runtime-rpc-smoke"
        path = $runtimeFile
    }
    $runtimeExec = Invoke-Rpc -Url "$baseUrl/rpc" -Id "rt-exec-run" -Method "exec.run" -Params @{
        sessionId = "runtime-rpc-smoke"
        command = $runtimeCommand
        timeoutMs = 1000
    }
    if (-not $runtimeWrite.Json.result.ok) {
        throw "file.write runtime smoke failed"
    }
    if ($runtimeRead.Content -notmatch 'runtime-smoke-file') {
        throw "file.read runtime smoke missing expected content"
    }
    if (-not $runtimeExec.Json.result.ok) {
        throw "exec.run runtime smoke failed"
    }
    if ($runtimeExec.Content -notmatch 'runtime-smoke-exec') {
        throw "exec.run runtime smoke missing expected stdout"
    }

    $wlStart = Invoke-Rpc -Url "$baseUrl/rpc" -Id "rt-wl-start" -Method "web.login.start" -Params @{
        provider = "chatgpt"
        model = "gpt-5.2"
    }
    $loginSessionId = "$($wlStart.Json.result.login.loginSessionId)"
    $loginCode = "$($wlStart.Json.result.login.code)"
    if ([string]::IsNullOrWhiteSpace($loginSessionId) -or [string]::IsNullOrWhiteSpace($loginCode)) {
        throw "web.login.start missing loginSessionId/code"
    }

    $wlWait = Invoke-Rpc -Url "$baseUrl/rpc" -Id "rt-wl-wait" -Method "web.login.wait" -Params @{
        loginSessionId = $loginSessionId
        timeoutMs = 20
    }
    $wlComplete = Invoke-Rpc -Url "$baseUrl/rpc" -Id "rt-wl-complete" -Method "web.login.complete" -Params @{
        loginSessionId = $loginSessionId
        code = $loginCode
    }
    $wlStatus = Invoke-Rpc -Url "$baseUrl/rpc" -Id "rt-wl-status" -Method "web.login.status" -Params @{
        loginSessionId = $loginSessionId
    }

    $sendStart = Invoke-Rpc -Url "$baseUrl/rpc" -Id "rt-tg-auth-start" -Method "send" -Params @{
        channel = "telegram"
        to = "runtime-smoke-room"
        sessionId = "runtime-smoke-session"
        message = "/auth start chatgpt"
    }
    $tgSession = "$($sendStart.Json.result.loginSessionId)"
    $tgCode = "$($sendStart.Json.result.loginCode)"
    if ([string]::IsNullOrWhiteSpace($tgSession) -or [string]::IsNullOrWhiteSpace($tgCode)) {
        throw "send(/auth start) missing loginSessionId/loginCode"
    }

    $sendComplete = Invoke-Rpc -Url "$baseUrl/rpc" -Id "rt-tg-auth-complete" -Method "send" -Params @{
        channel = "telegram"
        to = "runtime-smoke-room"
        sessionId = "runtime-smoke-session"
        message = "/auth complete chatgpt $tgCode $tgSession"
    }
    $sendChat = Invoke-Rpc -Url "$baseUrl/rpc" -Id "rt-tg-chat" -Method "send" -Params @{
        channel = "telegram"
        to = "runtime-smoke-room"
        sessionId = "runtime-smoke-session"
        message = "hello from runtime smoke"
    }
    $poll = Invoke-Rpc -Url "$baseUrl/rpc" -Id "rt-tg-poll" -Method "poll" -Params @{
        channel = "telegram"
        limit = 10
    }

    $pollCount = 0
    if ($poll.Json.result -and $poll.Json.result.count) {
        $pollCount = [int]$poll.Json.result.count
    }
    if ($pollCount -lt 1) {
        throw "poll returned zero updates"
    }

    Write-Output "SMOKE_HEALTH_HTTP=$($health.StatusCode)"
    Write-Output "SMOKE_STATUS_RPC_HTTP=$($statusRpc.StatusCode)"
    Write-Output "SMOKE_RUNTIME_WRITE_OK=$($runtimeWrite.Json.result.ok)"
    Write-Output "SMOKE_RUNTIME_READ_MATCH=$([bool]($runtimeRead.Content -match 'runtime-smoke-file'))"
    Write-Output "SMOKE_RUNTIME_EXEC_OK=$($runtimeExec.Json.result.ok)"
    Write-Output "SMOKE_RUNTIME_EXEC_STDOUT_MATCH=$([bool]($runtimeExec.Content -match 'runtime-smoke-exec'))"
    Write-Output "SMOKE_WEB_LOGIN_WAIT_STATUS=$($wlWait.Json.result.status)"
    Write-Output "SMOKE_WEB_LOGIN_COMPLETE_STATUS=$($wlComplete.Json.result.status)"
    Write-Output "SMOKE_WEB_LOGIN_STATUS_STATUS=$($wlStatus.Json.result.status)"
    Write-Output "SMOKE_TG_AUTH_COMPLETE_STATUS=$($sendComplete.Json.result.authStatus)"
    Write-Output "SMOKE_TG_CHAT_REPLY_HAS_OPENCLAW=$([bool]($sendChat.Content -match 'OpenClaw Zig'))"
    Write-Output "SMOKE_TG_POLL_COUNT=$pollCount"
}
finally {
    if ($null -ne $proc -and -not $proc.HasExited) {
        Stop-Process -Id $proc.Id -Force
    }
    Remove-Item Env:OPENCLAW_ZIG_HTTP_PORT -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $repo 'tmp_runtime_rpc_smoke.txt') -ErrorAction SilentlyContinue
    if (-not $KeepLogs) {
        Remove-Item $stdoutLog,$stderrLog -ErrorAction SilentlyContinue
    }
}
