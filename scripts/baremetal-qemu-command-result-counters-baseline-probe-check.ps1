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
    Write-Output 'BAREMETAL_QEMU_COMMAND_RESULT_COUNTERS_BASELINE_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying command-result counters probe failed with exit code $probeExitCode"
}

$preAck = Extract-IntValue -Text $probeText -Name 'PRE_ACK'
$preLastOpcode = Extract-IntValue -Text $probeText -Name 'PRE_LAST_OPCODE'
$preLastResult = Extract-IntValue -Text $probeText -Name 'PRE_LAST_RESULT'
$preTicks = Extract-IntValue -Text $probeText -Name 'PRE_TICKS'
$preMode = Extract-IntValue -Text $probeText -Name 'PRE_MODE'
$preHealthCode = Extract-IntValue -Text $probeText -Name 'PRE_HEALTH_CODE'
$preCounterTotal = Extract-IntValue -Text $probeText -Name 'PRE_COUNTER_TOTAL'
$preCounterLastSeq = Extract-IntValue -Text $probeText -Name 'PRE_COUNTER_LAST_SEQ'

if ($null -in @($preAck, $preLastOpcode, $preLastResult, $preTicks, $preMode, $preHealthCode, $preCounterTotal, $preCounterLastSeq)) {
    throw 'Missing baseline command-result counter fields.'
}
if ($preAck -ne 5) { throw "Expected PRE_ACK=5. got $preAck" }
if ($preLastOpcode -ne 54) { throw "Expected PRE_LAST_OPCODE=54. got $preLastOpcode" }
if ($preLastResult -ne -2) { throw "Expected PRE_LAST_RESULT=-2. got $preLastResult" }
if ($preTicks -lt 4) { throw "Expected PRE_TICKS>=4. got $preTicks" }
if ($preMode -ne 1) { throw "Expected PRE_MODE=1. got $preMode" }
if ($preHealthCode -ne 200) { throw "Expected PRE_HEALTH_CODE=200. got $preHealthCode" }
if ($preCounterTotal -ne 4) { throw "Expected PRE_COUNTER_TOTAL=4. got $preCounterTotal" }
if ($preCounterLastSeq -ne 5) { throw "Expected PRE_COUNTER_LAST_SEQ=5. got $preCounterLastSeq" }

Write-Output 'BAREMETAL_QEMU_COMMAND_RESULT_COUNTERS_BASELINE_PROBE=pass'
Write-Output "PRE_ACK=$preAck"
Write-Output "PRE_LAST_OPCODE=$preLastOpcode"
Write-Output "PRE_LAST_RESULT=$preLastResult"
Write-Output "PRE_TICKS=$preTicks"
Write-Output "PRE_MODE=$preMode"
Write-Output "PRE_HEALTH_CODE=$preHealthCode"
Write-Output "PRE_COUNTER_TOTAL=$preCounterTotal"
Write-Output "PRE_COUNTER_LAST_SEQ=$preCounterLastSeq"
