param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-command-result-counters-probe-check.ps1"

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
if ($probeExitCode -ne 0) {
    throw "Underlying command-result probe failed with exit code $probeExitCode"
}
if ($probeText -match 'BAREMETAL_QEMU_COMMAND_RESULT_COUNTERS_PROBE=skipped') {
    Write-Output "BAREMETAL_QEMU_RESET_COMMAND_RESULT_PRESERVE_RUNTIME_PROBE=skipped"
    exit 0
}

$postMode = Extract-IntValue -Text $probeText -Name "POST_MODE"
$postHealthCode = Extract-IntValue -Text $probeText -Name "POST_HEALTH_CODE"
$postCounterTotal = Extract-IntValue -Text $probeText -Name "POST_COUNTER_TOTAL"
$postCounterLastOpcode = Extract-IntValue -Text $probeText -Name "POST_COUNTER_LAST_OPCODE"
$postLastOpcode = Extract-IntValue -Text $probeText -Name "POST_LAST_OPCODE"
$postLastResult = Extract-IntValue -Text $probeText -Name "POST_LAST_RESULT"

if ($null -eq $postMode -or
    $null -eq $postHealthCode -or
    $null -eq $postCounterTotal -or
    $null -eq $postCounterLastOpcode -or
    $null -eq $postLastOpcode -or
    $null -eq $postLastResult) {
    throw "Missing expected command-result preservation fields in probe output."
}
if ($postMode -ne 1) {
    throw "Expected runtime mode to remain running after command_reset_command_result_counters. got $postMode"
}
if ($postHealthCode -ne 200) {
    throw "Expected health code to remain 200 after command_reset_command_result_counters. got $postHealthCode"
}
if ($postCounterTotal -ne 1) {
    throw "Expected command-result counters to collapse to one reset receipt. got total=$postCounterTotal"
}
if ($postCounterLastOpcode -ne 23 -or $postLastOpcode -ne 23) {
    throw "Expected reset-command-result opcode 23 in status and counters. got status=$postLastOpcode counters=$postCounterLastOpcode"
}
if ($postLastResult -ne 0) {
    throw "Expected reset-command-result to finish with result 0. got $postLastResult"
}

Write-Output "BAREMETAL_QEMU_RESET_COMMAND_RESULT_PRESERVE_RUNTIME_PROBE=pass"
Write-Output "POST_MODE=$postMode"
Write-Output "POST_HEALTH_CODE=$postHealthCode"
Write-Output "POST_COUNTER_TOTAL=$postCounterTotal"
Write-Output "POST_COUNTER_LAST_OPCODE=$postCounterLastOpcode"
Write-Output "POST_LAST_OPCODE=$postLastOpcode"
Write-Output "POST_LAST_RESULT=$postLastResult"
