param(
  [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"

& (Join-Path $PSScriptRoot "browser-request-direct-provider-success-smoke-check.ps1") `
  -Provider "opencode" `
  -ApiKey "testkey-opencode" `
  -ExpectedModel "opencode/default" `
  -SkipBuild:$SkipBuild

