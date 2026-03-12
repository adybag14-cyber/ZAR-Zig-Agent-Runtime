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

$port = 8095
$mockPort = 18082
$baseUrl = "http://127.0.0.1:$port"
$mockUrl = "http://127.0.0.1:$mockPort"
$token = 'fs2-telegram-token'

$stdoutLog = Join-Path $repo 'tmp_fs2_tg_webhook_stdout.log'
$stderrLog = Join-Path $repo 'tmp_fs2_tg_webhook_stderr.log'
$mockStdout = Join-Path $repo 'tmp_fs2_tg_webhook_mock_stdout.log'
$mockStderr = Join-Path $repo 'tmp_fs2_tg_webhook_mock_stderr.log'
$capturePath = Join-Path $repo 'tmp_fs2_tg_webhook_capture.jsonl'
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
  $incomingMessageId = 77
  $rpc = Invoke-Rpc $baseUrl @{
    id = 'tg-webhook-success'
    method = 'channels.telegram.webhook.receive'
    params = @{
      deliver = $true
      typingAction = 'typing'
      update = @{
        update_id = 42
        message = @{
          message_id = $incomingMessageId
          chat = @{ id = 12345; type = 'private' }
          from = @{ id = 88 }
          text = '/auth providers'
        }
      }
    }
  }

  $result = $rpc.Json.result
  if ($rpc.Response.StatusCode -ne 200) { throw 'channels.telegram.webhook.receive did not return HTTP 200' }
  if (-not $result.handled) { throw 'handled was false' }
  if ($result.status -notin @('processed','processed_with_delivery_error')) { throw "unexpected status: $($result.status)" }
  if (-not $result.send.accepted) { throw 'send.accepted was false' }
  if (-not $result.delivery.attempted) { throw 'delivery.attempted was false' }
  if (-not $result.delivery.ok) { throw 'delivery.ok was false' }
  if ([string]::IsNullOrWhiteSpace("$($result.send.reply)")) { throw 'send.reply was empty' }

  Start-Sleep -Milliseconds 500
  $records = Read-CaptureRecords $capturePath
  $sendRecords = @($records | Where-Object { $_.method -eq 'sendMessage' })
  $typingRecords = @($records | Where-Object { $_.method -eq 'sendChatAction' })
  if ($sendRecords.Count -lt 1) { throw 'expected at least one sendMessage call' }
  if ($typingRecords.Count -lt 1) { throw 'expected at least one sendChatAction call' }
  $firstSend = $sendRecords[0]
  if ($firstSend.body.chat_id -ne 12345) { throw 'sendMessage chat_id mismatch' }
  if ($firstSend.body.reply_to_message_id -ne $incomingMessageId) { throw 'reply_to_message_id mismatch' }
  if ("$($firstSend.body.text)" -ne "$($result.send.reply)") { throw 'captured Telegram text did not match runtime reply' }

  Write-Output "TELEGRAM_WEBHOOK_HTTP=$($rpc.Response.StatusCode)"
  Write-Output "TELEGRAM_WEBHOOK_HANDLED=$($result.handled)"
  Write-Output "TELEGRAM_WEBHOOK_STATUS=$($result.status)"
  Write-Output "TELEGRAM_WEBHOOK_DELIVERY_OK=$($result.delivery.ok)"
  Write-Output "TELEGRAM_WEBHOOK_SEND_ACCEPTED=$($result.send.accepted)"
  Write-Output "TELEGRAM_WEBHOOK_CAPTURE_SENDS=$($sendRecords.Count)"
  Write-Output "TELEGRAM_WEBHOOK_CAPTURE_TYPING=$($typingRecords.Count)"
  Write-Output "TELEGRAM_WEBHOOK_REPLY_TO_MATCH=$([bool]($firstSend.body.reply_to_message_id -eq $incomingMessageId))"
}
finally {
  if ($null -ne $serverProc -and -not $serverProc.HasExited) { Stop-Process -Id $serverProc.Id -Force }
  if ($null -ne $mockProc -and -not $mockProc.HasExited) { Stop-Process -Id $mockProc.Id -Force }
  Remove-Item Env:OPENCLAW_ZIG_HTTP_PORT -ErrorAction SilentlyContinue
  Remove-Item Env:OPENCLAW_ZIG_RUNTIME_TELEGRAM_API_ENDPOINT -ErrorAction SilentlyContinue
  Remove-Item Env:OPENCLAW_ZIG_TELEGRAM_BOT_TOKEN -ErrorAction SilentlyContinue
  Remove-Item $stdoutLog,$stderrLog,$mockStdout,$mockStderr,$capturePath -ErrorAction SilentlyContinue
}
