param(
  [switch]$SkipBuild
)
$ErrorActionPreference = 'Stop'

function Get-ZigPath {
  if ($env:OPENCLAW_ZIG_BIN -and $env:OPENCLAW_ZIG_BIN.Trim().Length -gt 0) { return $env:OPENCLAW_ZIG_BIN }
  return 'C:\Users\Ady\Documents\toolchains\zig-master\current\zig.exe'
}

function Get-OpenClawExecutable([string]$Repo) {
  $isWindowsHost = $env:OS -eq 'Windows_NT'
  $candidates = if ($isWindowsHost) {
    @(
      (Join-Path $Repo 'zig-out\bin\openclaw-zig.exe'),
      (Join-Path $Repo 'zig-out/bin/openclaw-zig.exe'),
      (Join-Path $Repo 'zig-out\bin\openclaw-zig'),
      (Join-Path $Repo 'zig-out/bin/openclaw-zig')
    )
  } else {
    @(
      (Join-Path $Repo 'zig-out\bin\openclaw-zig'),
      (Join-Path $Repo 'zig-out/bin/openclaw-zig'),
      (Join-Path $Repo 'zig-out\bin\openclaw-zig.exe'),
      (Join-Path $Repo 'zig-out/bin/openclaw-zig.exe')
    )
  }
  foreach ($candidate in $candidates) {
    if (Test-Path $candidate) { return $candidate }
  }
  throw 'openclaw-zig executable not found under zig-out/bin after build.'
}

function Get-PythonLaunch([string]$ScriptPath, [string[]]$ExtraArgs) {
  if (Get-Command python -ErrorAction SilentlyContinue) {
    return @{ FilePath = 'python'; Arguments = @($ScriptPath) + $ExtraArgs }
  }
  if (Get-Command python3 -ErrorAction SilentlyContinue) {
    return @{ FilePath = 'python3'; Arguments = @($ScriptPath) + $ExtraArgs }
  }
  if (Get-Command py -ErrorAction SilentlyContinue) {
    return @{ FilePath = 'py'; Arguments = @('-3', $ScriptPath) + $ExtraArgs }
  }
  throw 'Python runtime not found. Install python/python3 or py.'
}

function Wait-HttpReady([string]$Url, [int]$Attempts = 60) {
  for ($i = 0; $i -lt $Attempts; $i++) {
    try {
      $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 2
      if ($response.StatusCode -eq 200) { return }
    } catch {
      Start-Sleep -Milliseconds 500
    }
  }
  throw "endpoint did not become ready: $Url"
}

function Invoke-Rpc([string]$BaseUrl, [hashtable]$Payload) {
  $body = $Payload | ConvertTo-Json -Depth 12 -Compress
  $response = Invoke-WebRequest -Uri "$BaseUrl/rpc" -Method Post -ContentType 'application/json' -Body $body -UseBasicParsing
  $json = $response.Content | ConvertFrom-Json
  if (-not $json.result -and $json.chunks -and $json.chunks.Count -ge 1 -and $json.chunks[0].chunk) {
    $json = ($json.chunks[0].chunk | ConvertFrom-Json)
  }
  return @{
    Response = $response
    Json = $json
  }
}

function Get-LogTail([string]$Path, [int]$Lines = 120) {
  if (Test-Path $Path) { return (Get-Content $Path -Tail $Lines -ErrorAction SilentlyContinue) -join "`n" }
  return ''
}

function Read-CaptureRecords([string]$Path) {
  if (-not (Test-Path $Path)) { return @() }
  $records = @()
  foreach ($line in (Get-Content $Path | Where-Object { $_.Trim().Length -gt 0 })) {
    $records += ($line | ConvertFrom-Json)
  }
  return $records
}

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$zig = Get-ZigPath
if (-not (Test-Path $zig)) {
  throw "Zig binary not found at '$zig'. Set OPENCLAW_ZIG_BIN to a valid zig executable path."
}
if (-not $SkipBuild) {
  $null = & $zig build --summary all
}
$exe = Get-OpenClawExecutable $repo

$port = 8094
$mockPort = 18081
$baseUrl = "http://127.0.0.1:$port"
$mockUrl = "http://127.0.0.1:$mockPort"
$token = 'fs2-telegram-token'

$stdoutLog = Join-Path $repo 'tmp_fs2_tg_bot_send_stdout.log'
$stderrLog = Join-Path $repo 'tmp_fs2_tg_bot_send_stderr.log'
$mockStdout = Join-Path $repo 'tmp_fs2_tg_mock_stdout.log'
$mockStderr = Join-Path $repo 'tmp_fs2_tg_mock_stderr.log'
$capturePath = Join-Path $repo 'tmp_fs2_tg_bot_send_capture.jsonl'
Remove-Item $stdoutLog,$stderrLog,$mockStdout,$mockStderr,$capturePath -ErrorAction SilentlyContinue

$mockScript = Join-Path $repo 'scripts\telegram-bot-api-mock.py'
$python = Get-PythonLaunch $mockScript @('--port', "$mockPort", '--capture', $capturePath)
$mockProc = Start-Process -FilePath $python.FilePath -ArgumentList $python.Arguments -WorkingDirectory $repo -PassThru -RedirectStandardOutput $mockStdout -RedirectStandardError $mockStderr
Wait-HttpReady "$mockUrl/health"

$env:OPENCLAW_ZIG_HTTP_PORT = "$port"
$env:OPENCLAW_ZIG_RUNTIME_TELEGRAM_API_ENDPOINT = $mockUrl
$env:OPENCLAW_ZIG_TELEGRAM_BOT_TOKEN = $token
$serverProc = Start-Process -FilePath $exe -ArgumentList @('--serve') -WorkingDirectory $repo -PassThru -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog
Wait-HttpReady "$baseUrl/health"

try {
  $message = 'alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu'
  $rpc = Invoke-Rpc $baseUrl @{
    id = 'tg-bot-send-success'
    method = 'channels.telegram.bot.send'
    params = @{
      chatId = 12345
      message = $message
      deliver = $true
      stream = $true
      streamChunkChars = 16
      streamChunkDelayMs = 0
      typingAction = 'typing'
      typingIntervalMs = 1
    }
  }

  $result = $rpc.Json.result
  if ($rpc.Response.StatusCode -ne 200) { throw 'channels.telegram.bot.send did not return HTTP 200' }
  if ($result.status -ne 'ok') { throw "unexpected status: $($result.status)" }
  if (-not $result.delivery.attempted) { throw 'delivery.attempted was false' }
  if (-not $result.delivery.ok) { throw 'delivery.ok was false' }
  if ($result.deliveryBatch.chunkCount -lt 2) { throw 'expected chunked delivery' }
  if ($result.deliveryBatch.deliveredChunkCount -ne $result.deliveryBatch.chunkCount) { throw 'delivered chunk count did not match chunk count' }
  if ($result.deliveryBatch.messageIds.Count -ne $result.deliveryBatch.chunkCount) { throw 'messageIds count did not match chunk count' }
  if ($result.deliveryBatch.typingPulseCount -lt 1) { throw 'typingPulseCount did not show a live typing pulse' }

  Start-Sleep -Milliseconds 500
  $records = Read-CaptureRecords $capturePath
  $sendRecords = @($records | Where-Object { $_.method -eq 'sendMessage' })
  $typingRecords = @($records | Where-Object { $_.method -eq 'sendChatAction' })
  if ($sendRecords.Count -ne $result.deliveryBatch.chunkCount) { throw "expected $($result.deliveryBatch.chunkCount) sendMessage calls, found $($sendRecords.Count)" }
  if ($typingRecords.Count -lt 1) { throw 'expected at least one sendChatAction call' }
  foreach ($record in $sendRecords) {
    if ($record.body.chat_id -ne 12345) { throw 'sendMessage chat_id mismatch' }
    if (-not $record.body.text) { throw 'sendMessage text missing' }
    if ($record.body.reply_to_message_id) { throw 'bot.send should not set reply_to_message_id' }
  }

  Write-Output "TELEGRAM_BOT_SEND_HTTP=$($rpc.Response.StatusCode)"
  Write-Output "TELEGRAM_BOT_SEND_STATUS=$($result.status)"
  Write-Output "TELEGRAM_BOT_SEND_DELIVERY_OK=$($result.delivery.ok)"
  Write-Output "TELEGRAM_BOT_SEND_CHUNK_COUNT=$($result.deliveryBatch.chunkCount)"
  Write-Output "TELEGRAM_BOT_SEND_DELIVERED_COUNT=$($result.deliveryBatch.deliveredChunkCount)"
  Write-Output "TELEGRAM_BOT_SEND_TYPING_PULSES=$($result.deliveryBatch.typingPulseCount)"
  Write-Output "TELEGRAM_BOT_SEND_CAPTURE_SENDS=$($sendRecords.Count)"
  Write-Output "TELEGRAM_BOT_SEND_CAPTURE_TYPING=$($typingRecords.Count)"
}
finally {
  if ($null -ne $serverProc -and -not $serverProc.HasExited) { Stop-Process -Id $serverProc.Id -Force }
  if ($null -ne $mockProc -and -not $mockProc.HasExited) { Stop-Process -Id $mockProc.Id -Force }
  Remove-Item Env:OPENCLAW_ZIG_HTTP_PORT -ErrorAction SilentlyContinue
  Remove-Item Env:OPENCLAW_ZIG_RUNTIME_TELEGRAM_API_ENDPOINT -ErrorAction SilentlyContinue
  Remove-Item Env:OPENCLAW_ZIG_TELEGRAM_BOT_TOKEN -ErrorAction SilentlyContinue
  Remove-Item $stdoutLog,$stderrLog,$mockStdout,$mockStderr,$capturePath -ErrorAction SilentlyContinue
}
