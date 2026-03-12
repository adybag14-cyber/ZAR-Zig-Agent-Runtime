param(
  [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"

$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$defaultZig = "C:\Users\Ady\Documents\toolchains\zig-master\current\zig.exe"
$zig = if ($env:OPENCLAW_ZIG_BIN -and $env:OPENCLAW_ZIG_BIN.Trim().Length -gt 0) { $env:OPENCLAW_ZIG_BIN } else { $defaultZig }
if (-not (Test-Path $zig)) {
  throw "Zig binary not found at '$zig'. Set OPENCLAW_ZIG_BIN to a valid zig executable path."
}
if (-not $SkipBuild) {
  $null = & $zig build --summary all
}

function Resolve-FreeTcpPort {
  $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
  try {
    $listener.Start()
    return ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
  }
  finally {
    $listener.Stop()
  }
}

function Invoke-Rpc {
  param(
    [int]$Port,
    [string]$Id,
    [string]$Method,
    [hashtable]$Params = @{}
  )

  $payload = @{
    id = $Id
    method = $Method
    params = $Params
  } | ConvertTo-Json -Depth 10 -Compress

  $response = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/rpc" -Method Post -ContentType "application/json" -Body $payload -UseBasicParsing
  if ($response.StatusCode -ne 200) {
    throw "RPC $Method did not return HTTP 200"
  }
  return ($response.Content | ConvertFrom-Json)
}

function Read-Tail {
  param(
    [string]$Path,
    [int]$Lines = 120
  )
  if (Test-Path $Path) {
    return (Get-Content $Path -Tail $Lines -ErrorAction SilentlyContinue) -join "`n"
  }
  return ""
}

function Start-OpenClaw {
  param(
    [string]$Exe,
    [string]$Repo,
    [int]$Port,
    [string]$Name
  )

  $env:OPENCLAW_ZIG_HTTP_PORT = "$Port"
  $stdoutLog = Join-Path $Repo "tmp_${Name}_stdout.log"
  $stderrLog = Join-Path $Repo "tmp_${Name}_stderr.log"
  Remove-Item $stdoutLog,$stderrLog -ErrorAction SilentlyContinue

  $startProcessParams = @{
    FilePath = $Exe
    ArgumentList = @("--serve")
    WorkingDirectory = $Repo
    PassThru = $true
    RedirectStandardOutput = $stdoutLog
    RedirectStandardError = $stderrLog
  }
  if ($env:OS -eq "Windows_NT") {
    $startProcessParams.WindowStyle = "Hidden"
  }
  $proc = Start-Process @startProcessParams

  $ready = $false
  for ($i = 0; $i -lt 60; $i++) {
    if ($proc.HasExited) { break }
    try {
      $health = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/health" -UseBasicParsing -TimeoutSec 2
      if ($health.StatusCode -eq 200) {
        $ready = $true
        break
      }
    }
    catch {
      Start-Sleep -Milliseconds 500
    }
  }

  if (-not $ready) {
    $exitCode = if ($proc.HasExited) { $proc.ExitCode } else { "running" }
    throw "openclaw-zig server '$Name' did not become ready on port $Port (exit=$exitCode)`nSTDERR:`n$(Read-Tail $stderrLog)`nSTDOUT:`n$(Read-Tail $stdoutLog 60)"
  }

  return @{
    Process = $proc
    StdoutLog = $stdoutLog
    StderrLog = $stderrLog
  }
}

function Stop-OpenClaw {
  param($Server)
  if ($null -ne $Server -and $null -ne $Server.Process -and -not $Server.Process.HasExited) {
    Stop-Process -Id $Server.Process.Id -Force
    $Server.Process.WaitForExit()
  }
}

$isWindowsHost = $env:OS -eq "Windows_NT"
$exeCandidates = if ($isWindowsHost) {
  @(
    (Join-Path $repo "zig-out\bin\openclaw-zig.exe"),
    (Join-Path $repo "zig-out/bin/openclaw-zig.exe"),
    (Join-Path $repo "zig-out\bin\openclaw-zig"),
    (Join-Path $repo "zig-out/bin/openclaw-zig")
  )
} else {
  @(
    (Join-Path $repo "zig-out\bin\openclaw-zig"),
    (Join-Path $repo "zig-out/bin/openclaw-zig"),
    (Join-Path $repo "zig-out\bin\openclaw-zig.exe"),
    (Join-Path $repo "zig-out/bin/openclaw-zig.exe")
  )
}
$exe = $null
foreach ($candidate in $exeCandidates) {
  if (Test-Path $candidate) {
    $exe = $candidate
    break
  }
}
if (-not $exe) {
  throw "openclaw-zig executable not found under zig-out/bin after build."
}

$mockPort = Resolve-FreeTcpPort
$port1 = Resolve-FreeTcpPort
$port2 = Resolve-FreeTcpPort
$sessionId = "fs3-telegram-memory"
$stateDir = Join-Path $repo "tmp_fs3_telegram_memory_state"
$stateFile = Join-Path $stateDir "memory.json"
$mockStdoutLog = Join-Path $repo "tmp_fs3_telegram_memory_mock_stdout.log"
$mockStderrLog = Join-Path $repo "tmp_fs3_telegram_memory_mock_stderr.log"
$mockCapture = Join-Path $repo "tmp_fs3_telegram_memory_mock.jsonl"
$mockReady = Join-Path $repo "tmp_fs3_telegram_memory_mock.ready"
$mockScript = Join-Path $repo "tmp_fs3_telegram_memory_mock.ps1"
$apiKey = "sk-fs3-telegram-memory"

$previousHttpPort = $env:OPENCLAW_ZIG_HTTP_PORT
$previousStatePath = $env:OPENCLAW_ZIG_STATE_PATH
$previousBridgeEndpoint = $env:OPENCLAW_ZIG_LIGHTPANDA_ENDPOINT

Remove-Item $stateDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $stateDir | Out-Null
Remove-Item $mockStdoutLog,$mockStderrLog,$mockCapture,$mockReady,$mockScript -ErrorAction SilentlyContinue

$env:OPENCLAW_ZIG_STATE_PATH = $stateDir
$env:OPENCLAW_ZIG_LIGHTPANDA_ENDPOINT = "http://127.0.0.1:$mockPort"

@"
param(
  [int]`$Port,
  [string]`$CapturePath,
  [string]`$ReadyPath
)

`$ErrorActionPreference = "Stop"

function Read-ExactChars {
  param(
    [System.IO.StreamReader]`$Reader,
    [int]`$Count
  )
  if (`$Count -le 0) { return "" }
  `$buffer = New-Object char[] `$Count
  `$read = 0
  while (`$read -lt `$Count) {
    `$chunk = `$Reader.Read(`$buffer, `$read, `$Count - `$read)
    if (`$chunk -le 0) { break }
    `$read += `$chunk
  }
  if (`$read -le 0) { return "" }
  return (-join `$buffer[0..(`$read - 1)])
}

function Write-JsonResponse {
  param(
    [System.Net.Sockets.TcpClient]`$Client,
    [int]`$StatusCode,
    [string]`$StatusText,
    [string]`$Body
  )
  `$stream = `$Client.GetStream()
  `$bodyBytes = [System.Text.Encoding]::UTF8.GetBytes(`$Body)
  `$header = "HTTP/1.1 `$StatusCode `$StatusText`r`nContent-Type: application/json`r`nContent-Length: `$(`$bodyBytes.Length)`r`nConnection: close`r`n`r`n"
  `$headerBytes = [System.Text.Encoding]::ASCII.GetBytes(`$header)
  `$stream.Write(`$headerBytes, 0, `$headerBytes.Length)
  `$stream.Write(`$bodyBytes, 0, `$bodyBytes.Length)
  `$stream.Flush()
}

`$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, `$Port)
`$listener.Start()
Set-Content -Path `$ReadyPath -Value "ready" -NoNewline

try {
  `$handledCompletion = `$false
  while (-not `$handledCompletion) {
    `$client = `$listener.AcceptTcpClient()
    try {
      `$stream = `$client.GetStream()
      `$reader = [System.IO.StreamReader]::new(`$stream, [System.Text.Encoding]::ASCII, `$false, 1024, `$true)
      try {
        `$requestLine = `$reader.ReadLine()
        if ([string]::IsNullOrWhiteSpace(`$requestLine)) {
          Write-JsonResponse -Client `$client -StatusCode 400 -StatusText "Bad Request" -Body '{"error":"empty request"}'
          continue
        }

        `$headerMap = @{}
        while (`$true) {
          `$line = `$reader.ReadLine()
          if (`$null -eq `$line -or `$line.Length -eq 0) { break }
          `$separator = `$line.IndexOf(':')
          if (`$separator -gt 0) {
            `$name = `$line.Substring(0, `$separator).Trim().ToLowerInvariant()
            `$value = `$line.Substring(`$separator + 1).Trim()
            `$headerMap[`$name] = `$value
          }
        }

        `$contentLength = 0
        if (`$headerMap.ContainsKey("content-length")) {
          [void][int]::TryParse(`$headerMap["content-length"], [ref]`$contentLength)
        }
        `$body = Read-ExactChars -Reader `$reader -Count `$contentLength

        `$parts = `$requestLine.Split(' ')
        `$method = if (`$parts.Length -ge 1) { `$parts[0] } else { "" }
        `$path = if (`$parts.Length -ge 2) { `$parts[1] } else { "/" }
        @{
          method = `$method
          path = `$path
          body = `$body
        } | ConvertTo-Json -Compress | Add-Content -Path `$CapturePath

        if (`$method -eq "GET" -and `$path -eq "/json/version") {
          Write-JsonResponse -Client `$client -StatusCode 200 -StatusText "OK" -Body '{"Browser":"OpenClaw FS3 Telegram Mock","Protocol-Version":"1.3"}'
          continue
        }

        if (`$method -eq "POST" -and `$path -eq "/v1/chat/completions") {
          Write-JsonResponse -Client `$client -StatusCode 200 -StatusText "OK" -Body '{"model":"gpt-5.2","output_text":"mock telegram memory completion from zig"}'
          `$handledCompletion = `$true
          continue
        }

        Write-JsonResponse -Client `$client -StatusCode 404 -StatusText "Not Found" -Body '{"error":"not found"}'
      }
      finally {
        `$reader.Dispose()
      }
    }
    finally {
      `$client.Close()
    }
  }
}
finally {
  `$listener.Stop()
}
"@ | Set-Content -Path $mockScript -NoNewline

$shellExe = (Get-Process -Id $PID).Path
$mockArgumentList = @("-NoProfile", "-File", $mockScript, "-Port", "$mockPort", "-CapturePath", $mockCapture, "-ReadyPath", $mockReady)
if ($isWindowsHost) {
  $mockArgumentList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $mockScript, "-Port", "$mockPort", "-CapturePath", $mockCapture, "-ReadyPath", $mockReady)
}
$mockStartProcessParams = @{
  FilePath = $shellExe
  ArgumentList = $mockArgumentList
  WorkingDirectory = $repo
  PassThru = $true
  RedirectStandardOutput = $mockStdoutLog
  RedirectStandardError = $mockStderrLog
}
if ($isWindowsHost) {
  $mockStartProcessParams.WindowStyle = "Hidden"
}
$mockProc = Start-Process @mockStartProcessParams

$mockReadyOk = $false
for ($i = 0; $i -lt 40; $i++) {
  if ($mockProc.HasExited) { break }
  if (Test-Path $mockReady) {
    $mockReadyOk = $true
    break
  }
  Start-Sleep -Milliseconds 250
}
if (-not $mockReadyOk) {
  $exitCode = if ($mockProc.HasExited) { $mockProc.ExitCode } else { "running" }
  throw "mock telegram bridge did not become ready on port $mockPort (exit=$exitCode)`nSTDERR:`n$(Read-Tail $mockStderrLog)`nSTDOUT:`n$(Read-Tail $mockStdoutLog 60)"
}

$server1 = $null
$server2 = $null
try {
  $server1 = Start-OpenClaw -Exe $exe -Repo $repo -Port $port1 -Name "fs3_telegram_memory_server1"

  $null = Invoke-Rpc -Port $port1 -Id "fs3-telegram-inject-1" -Method "chat.inject" -Params @{ sessionId = $sessionId; channel = "telegram"; message = "Project codename Kite" }
  $null = Invoke-Rpc -Port $port1 -Id "fs3-telegram-inject-2" -Method "chat.inject" -Params @{ sessionId = $sessionId; channel = "telegram"; message = "Release target Aurora" }

  $before = Invoke-Rpc -Port $port1 -Id "fs3-telegram-memory-before" -Method "doctor.memory.status" -Params @{}
  if (-not $before.result) { throw "doctor.memory.status before restart missing result" }
  if (-not $before.result.persistent) { throw "memory store should be persistent before restart" }
  if ($before.result.entryCount -ne 2) { throw "unexpected pre-restart memory entry count: $($before.result.entryCount)" }
  if ($before.result.statePath -ne $stateFile) { throw "unexpected pre-restart memory state path: $($before.result.statePath)" }

  Stop-OpenClaw $server1
  $server1 = $null

  $server2 = Start-OpenClaw -Exe $exe -Repo $repo -Port $port2 -Name "fs3_telegram_memory_server2"

  $after = Invoke-Rpc -Port $port2 -Id "fs3-telegram-memory-after" -Method "doctor.memory.status" -Params @{}
  if (-not $after.result) { throw "doctor.memory.status after restart missing result" }
  if (-not $after.result.persistent) { throw "memory store should be persistent after restart" }
  if ($after.result.entryCount -ne 2) { throw "unexpected post-restart memory entry count: $($after.result.entryCount)" }
  if ($after.result.statePath -ne $stateFile) { throw "unexpected post-restart memory state path: $($after.result.statePath)" }

  $setResult = Invoke-Rpc -Port $port2 -Id "fs3-telegram-set-key" -Method "send" -Params @{
    channel = "telegram"
    to = "fs3-room"
    sessionId = $sessionId
    message = "/set api key chatgpt $apiKey"
  }
  if (-not $setResult.result) { throw "/set api key result missing" }
  if ($setResult.result.commandName -ne "set") { throw "/set api key did not produce set command result" }

  $chatResult = Invoke-Rpc -Port $port2 -Id "fs3-telegram-chat" -Method "send" -Params @{
    channel = "telegram"
    to = "fs3-room"
    sessionId = $sessionId
    message = "What is the project codename from memory?"
  }
  if (-not $chatResult.result) { throw "telegram chat result missing" }
  $chatReplySource = "$($chatResult.result.replySource)"
  $chatProviderApiKeyUsed = [bool]$chatResult.result.providerApiKeyUsed
  $chatProvider = "$($chatResult.result.provider)"
  $chatAuthStatus = "$($chatResult.result.authStatus)"
  $chatReply = "$($chatResult.result.reply)"

  for ($i = 0; $i -lt 40; $i++) {
    if (Test-Path $mockCapture) {
      $lineCount = (Get-Content $mockCapture -ErrorAction SilentlyContinue).Count
      if ($lineCount -ge 1) { break }
    }
    Start-Sleep -Milliseconds 250
  }
  if (-not (Test-Path $mockCapture)) { throw "mock capture file missing" }
  $captureLines = Get-Content $mockCapture | Where-Object { $_.Trim().Length -gt 0 }
  if ($captureLines.Count -lt 1) { throw "mock bridge did not record the telegram completion request" }
  $completionCapture = ($captureLines | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object { $_.method -eq "POST" -and $_.path -eq "/v1/chat/completions" } | Select-Object -First 1)
  if ($null -eq $completionCapture) {
    throw "missing telegram POST /v1/chat/completions capture (replySource=$chatReplySource providerApiKeyUsed=$chatProviderApiKeyUsed provider=$chatProvider authStatus=$chatAuthStatus reply=$chatReply)"
  }
  $completionBody = $completionCapture.body | ConvertFrom-Json
  if ($completionBody.provider -ne "chatgpt") { throw "telegram completion payload provider mismatch" }
  if ($completionBody.apiKey -ne $apiKey) { throw "telegram completion payload apiKey mismatch" }
  $recallMessage = @($completionBody.messages | Where-Object { $_.role -eq "system" -and $_.content -match "Long-term memory recall query:" }) | Select-Object -Last 1
  if ($null -eq $recallMessage) { throw "telegram completion payload did not include recall context system message" }
  if ($recallMessage.content -notmatch [regex]::Escape("Long-term memory recall query: What is the project codename from memory?")) { throw "telegram recall query line missing" }
  if ($recallMessage.content -notmatch [regex]::Escape("Semantic recall hits:")) { throw "telegram recall semantic section missing" }
  if ($recallMessage.content -notmatch [regex]::Escape("Project codename Kite")) { throw "telegram recall codename hit missing" }
  if ($chatReplySource -ne "bridge_completion") { throw "telegram reply did not use bridge completion (provider=$chatProvider authStatus=$chatAuthStatus providerApiKeyUsed=$chatProviderApiKeyUsed reply=$chatReply)" }
  if (-not $chatProviderApiKeyUsed) { throw "telegram reply did not use provider API key (replySource=$chatReplySource provider=$chatProvider authStatus=$chatAuthStatus reply=$chatReply)" }
  if ($chatProvider -ne "chatgpt") { throw "telegram reply provider mismatch: $chatProvider" }
  if ($chatAuthStatus -ne "authorized") { throw "telegram reply auth status mismatch: $chatAuthStatus" }
  if ($chatReply -ne "mock telegram memory completion from zig") { throw "unexpected telegram completion text: $chatReply" }

  Write-Output "FS3_TELEGRAM_MEMORY_HTTP=200"
  Write-Output "FS3_TELEGRAM_MEMORY_ENTRY_COUNT=$($after.result.entryCount)"
  Write-Output "FS3_TELEGRAM_MEMORY_STATE_PATH=$($after.result.statePath)"
  Write-Output "FS3_TELEGRAM_MEMORY_REPLY_SOURCE=$chatReplySource"
  Write-Output "FS3_TELEGRAM_MEMORY_PROVIDER_API_KEY_USED=$chatProviderApiKeyUsed"
  Write-Output "FS3_TELEGRAM_MEMORY_REPLY=$chatReply"
}
finally {
  Stop-OpenClaw $server1
  Stop-OpenClaw $server2
  if ($null -ne $mockProc -and -not $mockProc.HasExited) {
    Stop-Process -Id $mockProc.Id -Force
    $mockProc.WaitForExit()
  }
  Remove-Item $stateDir -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item $mockStdoutLog,$mockStderrLog,$mockCapture,$mockReady,$mockScript -ErrorAction SilentlyContinue
  Get-ChildItem -Path $repo -Filter "tmp_fs3_telegram_memory_server*.log" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
  if ($null -eq $previousHttpPort) { Remove-Item Env:OPENCLAW_ZIG_HTTP_PORT -ErrorAction SilentlyContinue } else { $env:OPENCLAW_ZIG_HTTP_PORT = $previousHttpPort }
  if ($null -eq $previousStatePath) { Remove-Item Env:OPENCLAW_ZIG_STATE_PATH -ErrorAction SilentlyContinue } else { $env:OPENCLAW_ZIG_STATE_PATH = $previousStatePath }
  if ($null -eq $previousBridgeEndpoint) { Remove-Item Env:OPENCLAW_ZIG_LIGHTPANDA_ENDPOINT -ErrorAction SilentlyContinue } else { $env:OPENCLAW_ZIG_LIGHTPANDA_ENDPOINT = $previousBridgeEndpoint }
}
