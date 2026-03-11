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
    Write-Output 'BAREMETAL_QEMU_COMMAND_RESULT_COUNTERS_NOT_SUPPORTED_BUCKET_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying command-result counters probe failed with exit code $probeExitCode"
}

$preCounterNotSupported = Extract-IntValue -Text $probeText -Name 'PRE_COUNTER_NOT_SUPPORTED'
$preCounterTotal = Extract-IntValue -Text $probeText -Name 'PRE_COUNTER_TOTAL'
$preCounterLastSeq = Extract-IntValue -Text $probeText -Name 'PRE_COUNTER_LAST_SEQ'

if ($null -in @($preCounterNotSupported, $preCounterTotal, $preCounterLastSeq)) {
    throw 'Missing not-supported command-result fields.'
}
if ($preCounterNotSupported -ne 1) { throw "Expected PRE_COUNTER_NOT_SUPPORTED=1. got $preCounterNotSupported" }
if ($preCounterTotal -ne 4) { throw "Expected PRE_COUNTER_TOTAL=4. got $preCounterTotal" }
if ($preCounterLastSeq -ne 5) { throw "Expected PRE_COUNTER_LAST_SEQ=5. got $preCounterLastSeq" }

Write-Output 'BAREMETAL_QEMU_COMMAND_RESULT_COUNTERS_NOT_SUPPORTED_BUCKET_PROBE=pass'
Write-Output "PRE_COUNTER_NOT_SUPPORTED=$preCounterNotSupported"
Write-Output "PRE_COUNTER_TOTAL=$preCounterTotal"
Write-Output "PRE_COUNTER_LAST_SEQ=$preCounterLastSeq"
