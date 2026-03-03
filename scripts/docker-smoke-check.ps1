$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$defaultZig = "C:\Users\Ady\Documents\toolchains\zig-master\current\zig.exe"
$zig = if ($env:OPENCLAW_ZIG_BIN -and $env:OPENCLAW_ZIG_BIN.Trim().Length -gt 0) { $env:OPENCLAW_ZIG_BIN } else { $defaultZig }
if (-not (Test-Path $zig)) {
  throw "Zig binary not found at '$zig'. Set OPENCLAW_ZIG_BIN to a valid zig executable path."
}
$null = & $zig build --summary all
$exe = Join-Path $repo "zig-out\bin\openclaw-zig.exe"
if (-not (Test-Path $exe)) {
  throw "openclaw-zig executable not found at '$exe' after build."
}
$port = 8091
$env:OPENCLAW_ZIG_HTTP_PORT = "$port"
$stdoutLog = Join-Path $repo "tmp_smoke_docker_stdout.log"
$stderrLog = Join-Path $repo "tmp_smoke_docker_stderr.log"
Remove-Item $stdoutLog,$stderrLog -ErrorAction SilentlyContinue
$proc = Start-Process -FilePath $exe -ArgumentList @("--serve") -WorkingDirectory $repo -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog

$ready = $false
for ($i = 0; $i -lt 60; $i++) {
  if ($proc.HasExited) {
    break
  }
  try {
    $health = Invoke-WebRequest -Uri "http://127.0.0.1:$port/health" -UseBasicParsing -TimeoutSec 2
    if ($health.StatusCode -eq 200) {
      $ready = $true
      break
    }
  } catch {
    Start-Sleep -Milliseconds 500
  }
}

if (-not $ready) {
  $stderrTail = if (Test-Path $stderrLog) { (Get-Content $stderrLog -Tail 120 -ErrorAction SilentlyContinue) -join "`n" } else { "" }
  $stdoutTail = if (Test-Path $stdoutLog) { (Get-Content $stdoutLog -Tail 60 -ErrorAction SilentlyContinue) -join "`n" } else { "" }
  $exitCode = if ($proc.HasExited) { $proc.ExitCode } else { "running" }
  throw "openclaw-zig server did not become ready on port $port (exit=$exitCode)`nSTDERR:`n$stderrTail`nSTDOUT:`n$stdoutTail"
}

try {
  $health = Invoke-WebRequest -Uri "http://127.0.0.1:$port/health" -UseBasicParsing
  $rpcBody = '{"id":"dock-smoke","method":"status","params":{}}'
  $rpc = Invoke-WebRequest -Uri "http://127.0.0.1:$port/rpc" -Method Post -ContentType "application/json" -Body $rpcBody -UseBasicParsing

  $dockerHealthCode = docker run --rm curlimages/curl:8.12.1 -s -o /dev/null -w "%{http_code}" "http://host.docker.internal:$port/health"
  $dockerRpcCode = docker run --rm curlimages/curl:8.12.1 -s -o /dev/null -w "%{http_code}" -H "Content-Type: application/json" -d $rpcBody "http://host.docker.internal:$port/rpc"

  Write-Output "HOST_HEALTH_HTTP=$($health.StatusCode)"
  Write-Output "HOST_RPC_HTTP=$($rpc.StatusCode)"
  Write-Output "HOST_RPC_BODY=$($rpc.Content)"
  Write-Output "DOCKER_HEALTH_HTTP=$dockerHealthCode"
  Write-Output "DOCKER_RPC_HTTP=$dockerRpcCode"
}
finally {
  if ($null -ne $proc -and -not $proc.HasExited) {
    Stop-Process -Id $proc.Id -Force
  }
  Remove-Item $stdoutLog,$stderrLog -ErrorAction SilentlyContinue
  Remove-Item Env:OPENCLAW_ZIG_HTTP_PORT -ErrorAction SilentlyContinue
}
