# SPDX-License-Identifier: GPL-2.0-only
param(
  [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"

& (Join-Path $PSScriptRoot "browser-request-direct-provider-success-smoke-check.ps1") `
  -Provider "openrouter" `
  -ApiKey "testkey-openrouter" `
  -ExpectedModel "openrouter/auto" `
  -SkipBuild:$SkipBuild
