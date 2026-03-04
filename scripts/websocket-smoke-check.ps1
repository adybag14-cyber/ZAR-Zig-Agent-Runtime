param(
    [int] $Port = 8096,
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

    throw "Zig executable not found. Set OPENCLAW_ZIG_BIN or ensure zig is on PATH."
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

$zig = Resolve-ZigExecutable
if (-not $SkipBuild) {
    & $zig build --summary all
    if ($LASTEXITCODE -ne 0) {
        throw "zig build failed with exit code $LASTEXITCODE"
    }
}

$exe = Resolve-AgentExecutable -RepoPath $repo

$env:OPENCLAW_ZIG_HTTP_PORT = "$Port"
$stdoutLog = Join-Path $repo "tmp_smoke_ws_stdout.log"
$stderrLog = Join-Path $repo "tmp_smoke_ws_stderr.log"
Remove-Item $stdoutLog,$stderrLog -ErrorAction SilentlyContinue

$proc = Start-Process -FilePath $exe -ArgumentList @("--serve") -WorkingDirectory $repo -PassThru -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog
$baseUrl = "http://127.0.0.1:$Port"
$wsUri = [Uri]::new("ws://127.0.0.1:$Port/ws")
$wsRootUri = [Uri]::new("ws://127.0.0.1:$Port/")

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
    $ws = [System.Net.WebSockets.ClientWebSocket]::new()
    $cts = [System.Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds(15))
    $null = $ws.ConnectAsync($wsUri, $cts.Token).GetAwaiter().GetResult()

    $requestPayload = '{"id":"ws-smoke-1","method":"status","params":{}}'
    $requestBytes = [System.Text.Encoding]::UTF8.GetBytes($requestPayload)
    $requestSegment = [ArraySegment[byte]]::new($requestBytes)
    $null = $ws.SendAsync($requestSegment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [System.Threading.CancellationToken]::None).GetAwaiter().GetResult()

    $buffer = New-Object byte[] 16384
    $builder = [System.Text.StringBuilder]::new()
    do {
        $segment = [ArraySegment[byte]]::new($buffer)
        $receive = $ws.ReceiveAsync($segment, [System.Threading.CancellationToken]::None).GetAwaiter().GetResult()
        if ($receive.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
            throw "websocket closed before response frame was received"
        }
        $chunk = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $receive.Count)
        [void]$builder.Append($chunk)
    } while (-not $receive.EndOfMessage)

    $responseText = $builder.ToString()
    $responseJson = $responseText | ConvertFrom-Json
    if ($null -eq $responseJson.result) {
        throw "websocket response missing result payload: $responseText"
    }

    $serviceValue = "$($responseJson.result.service)"
    if ([string]::IsNullOrWhiteSpace($serviceValue)) {
        throw "websocket status rpc returned missing service payload: $responseText"
    }

    Write-Output "WS_SMOKE_CONNECT=ok"
    Write-Output "WS_SMOKE_REPLY_HAS_RESULT=True"
    Write-Output "WS_SMOKE_SERVICE=$serviceValue"

    try {
        $null = $ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "smoke-complete", [System.Threading.CancellationToken]::None).GetAwaiter().GetResult()
    } catch {
        # Server-side close without full handshake is acceptable for this smoke.
    }

    # Root websocket compatibility route (ws://host:port/) parity check.
    $wsRoot = [System.Net.WebSockets.ClientWebSocket]::new()
    $rootCts = [System.Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds(15))
    $null = $wsRoot.ConnectAsync($wsRootUri, $rootCts.Token).GetAwaiter().GetResult()

    $rootRequestPayload = '{"id":"ws-smoke-root-1","method":"health","params":{}}'
    $rootRequestBytes = [System.Text.Encoding]::UTF8.GetBytes($rootRequestPayload)
    $rootRequestSegment = [ArraySegment[byte]]::new($rootRequestBytes)
    $null = $wsRoot.SendAsync($rootRequestSegment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [System.Threading.CancellationToken]::None).GetAwaiter().GetResult()

    $rootBuffer = New-Object byte[] 16384
    $rootBuilder = [System.Text.StringBuilder]::new()
    do {
        $rootSegment = [ArraySegment[byte]]::new($rootBuffer)
        $rootReceive = $wsRoot.ReceiveAsync($rootSegment, [System.Threading.CancellationToken]::None).GetAwaiter().GetResult()
        if ($rootReceive.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
            throw "root websocket compatibility route closed before response frame was received"
        }
        $rootChunk = [System.Text.Encoding]::UTF8.GetString($rootBuffer, 0, $rootReceive.Count)
        [void]$rootBuilder.Append($rootChunk)
    } while (-not $rootReceive.EndOfMessage)

    $rootResponseText = $rootBuilder.ToString()
    $rootResponseJson = $rootResponseText | ConvertFrom-Json
    if ($null -eq $rootResponseJson.result) {
        throw "root websocket response missing result payload: $rootResponseText"
    }
    $rootStatus = "$($rootResponseJson.result.status)"
    if ([string]::IsNullOrWhiteSpace($rootStatus) -or $rootStatus -ne "ok") {
        throw "root websocket response unexpected health status: $rootResponseText"
    }
    Write-Output "WS_ROOT_COMPAT_CONNECT=ok"
    Write-Output "WS_ROOT_COMPAT_STATUS=$rootStatus"

    try {
        $null = $wsRoot.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "smoke-complete", [System.Threading.CancellationToken]::None).GetAwaiter().GetResult()
    } catch {
        # Server-side close without full handshake is acceptable for this smoke.
    }
}
finally {
    if ($null -ne $proc -and -not $proc.HasExited) {
        Stop-Process -Id $proc.Id -Force
    }
    Remove-Item Env:OPENCLAW_ZIG_HTTP_PORT -ErrorAction SilentlyContinue
    if (-not $KeepLogs) {
        Remove-Item $stdoutLog,$stderrLog -ErrorAction SilentlyContinue
    }
}
