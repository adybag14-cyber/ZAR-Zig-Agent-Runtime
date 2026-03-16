# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-vector-history-clear-probe-check.ps1"

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $pattern = '(?m)^' + [regex]::Escape($Name) + '=(-?\d+)$'
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$probeOutput = if ($SkipBuild) { & $probe -SkipBuild 2>&1 } else { & $probe 2>&1 }
$probeExitCode = $LASTEXITCODE
$probeText = ($probeOutput | Out-String)
$probeOutput | Write-Output
if ($probeText -match 'BAREMETAL_QEMU_VECTOR_HISTORY_CLEAR_PROBE=skipped') {
    Write-Output 'BAREMETAL_QEMU_VECTOR_HISTORY_CLEAR_PRE_EXCEPTION_PAYLOAD_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying vector-history-clear probe failed with exit code $probeExitCode"
}

$preExceptionCount = Extract-IntValue -Text $probeText -Name 'PRE_EXCEPTION_COUNT'
$preExceptionHistoryLen = Extract-IntValue -Text $probeText -Name 'PRE_EXCEPTION_HISTORY_LEN'
$preException0Seq = Extract-IntValue -Text $probeText -Name 'PRE_EXCEPTION0_SEQ'
$preException0Vector = Extract-IntValue -Text $probeText -Name 'PRE_EXCEPTION0_VECTOR'
$preException0Code = Extract-IntValue -Text $probeText -Name 'PRE_EXCEPTION0_CODE'

if ($null -in @($preExceptionCount, $preExceptionHistoryLen, $preException0Seq, $preException0Vector, $preException0Code)) {
    throw 'Missing pre-exception payload fields in probe output.'
}
if ($preExceptionCount -ne 1) { throw "Expected PRE_EXCEPTION_COUNT=1. got $preExceptionCount" }
if ($preExceptionHistoryLen -ne 1) { throw "Expected PRE_EXCEPTION_HISTORY_LEN=1. got $preExceptionHistoryLen" }
if ($preException0Seq -ne 1 -or $preException0Vector -ne 13 -or $preException0Code -ne 51966) {
    throw "Unexpected exception payload: seq=$preException0Seq vector=$preException0Vector code=$preException0Code"
}

Write-Output 'BAREMETAL_QEMU_VECTOR_HISTORY_CLEAR_PRE_EXCEPTION_PAYLOAD_PROBE=pass'
Write-Output "PRE_EXCEPTION0_SEQ=$preException0Seq"
Write-Output "PRE_EXCEPTION0_VECTOR=$preException0Vector"
Write-Output "PRE_EXCEPTION0_CODE=$preException0Code"
