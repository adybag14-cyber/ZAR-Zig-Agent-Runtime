param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-command-result-counters-probe-check.ps1"

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $pattern = '(?m)^' + [regex]::Escape($Name) + '=(-?\d+)\r?$'
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$probeOutput = if ($SkipBuild) { & $probe -SkipBuild 2>&1 } else { & $probe 2>&1 }
$probeExitCode = $LASTEXITCODE
$probeText = ($probeOutput | Out-String)
$probeOutput | Write-Output
if ($probeText -match 'BAREMETAL_QEMU_COMMAND_RESULT_COUNTERS_PROBE=skipped') {
    Write-Output 'BAREMETAL_QEMU_COMMAND_RESULT_COUNTERS_OTHER_ERROR_BUCKET_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying command-result counters probe failed with exit code $probeExitCode"
}

$preCounterOther = Extract-IntValue -Text $probeText -Name 'PRE_COUNTER_OTHER'
$preCounterLastOpcode = Extract-IntValue -Text $probeText -Name 'PRE_COUNTER_LAST_OPCODE'
$preCounterLastResult = Extract-IntValue -Text $probeText -Name 'PRE_COUNTER_LAST_RESULT'

if ($null -in @($preCounterOther, $preCounterLastOpcode, $preCounterLastResult)) {
    throw 'Missing other-error command-result fields.'
}
if ($preCounterOther -ne 1) { throw "Expected PRE_COUNTER_OTHER=1. got $preCounterOther" }
if ($preCounterLastOpcode -ne 54) { throw "Expected PRE_COUNTER_LAST_OPCODE=54. got $preCounterLastOpcode" }
if ($preCounterLastResult -ne -2) { throw "Expected PRE_COUNTER_LAST_RESULT=-2. got $preCounterLastResult" }

Write-Output 'BAREMETAL_QEMU_COMMAND_RESULT_COUNTERS_OTHER_ERROR_BUCKET_PROBE=pass'
Write-Output "PRE_COUNTER_OTHER=$preCounterOther"
Write-Output "PRE_COUNTER_LAST_OPCODE=$preCounterLastOpcode"
Write-Output "PRE_COUNTER_LAST_RESULT=$preCounterLastResult"
