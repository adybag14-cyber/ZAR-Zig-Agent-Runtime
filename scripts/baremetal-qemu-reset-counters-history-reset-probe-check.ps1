param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-reset-counters-probe-check.ps1"

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
if ($probeText -match 'BAREMETAL_QEMU_RESET_COUNTERS_PROBE=skipped') {
    Write-Output 'BAREMETAL_QEMU_RESET_COUNTERS_HISTORY_RESET_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying reset-counters probe failed with exit code $probeExitCode"
}

$preCommandHistoryLen = Extract-IntValue -Text $probeText -Name "PRE_COMMAND_HISTORY_LEN"
$preHealthHistoryLen = Extract-IntValue -Text $probeText -Name "PRE_HEALTH_HISTORY_LEN"
$preModeHistoryLen = Extract-IntValue -Text $probeText -Name "PRE_MODE_HISTORY_LEN"
$preBootHistoryLen = Extract-IntValue -Text $probeText -Name "PRE_BOOT_HISTORY_LEN"
$postCommandHistoryLen = Extract-IntValue -Text $probeText -Name "POST_COMMAND_HISTORY_LEN"
$postCommandHistoryFirstSeq = Extract-IntValue -Text $probeText -Name "POST_COMMAND_HISTORY_FIRST_SEQ"
$postCommandHistoryFirstOpcode = Extract-IntValue -Text $probeText -Name "POST_COMMAND_HISTORY_FIRST_OPCODE"
$postHealthHistoryLen = Extract-IntValue -Text $probeText -Name "POST_HEALTH_HISTORY_LEN"
$postHealthHistoryFirstCode = Extract-IntValue -Text $probeText -Name "POST_HEALTH_HISTORY_FIRST_CODE"
$postHealthHistoryFirstAck = Extract-IntValue -Text $probeText -Name "POST_HEALTH_HISTORY_FIRST_ACK"
$postModeHistoryLen = Extract-IntValue -Text $probeText -Name "POST_MODE_HISTORY_LEN"
$postBootHistoryLen = Extract-IntValue -Text $probeText -Name "POST_BOOT_HISTORY_LEN"

if ($null -in @($preCommandHistoryLen,$preHealthHistoryLen,$preModeHistoryLen,$preBootHistoryLen,$postCommandHistoryLen,$postCommandHistoryFirstSeq,$postCommandHistoryFirstOpcode,$postHealthHistoryLen,$postHealthHistoryFirstCode,$postHealthHistoryFirstAck,$postModeHistoryLen,$postBootHistoryLen)) {
    throw "Missing history reset fields in probe output."
}
if ($preCommandHistoryLen -lt 12 -or $preHealthHistoryLen -lt 12 -or $preModeHistoryLen -lt 2 -or $preBootHistoryLen -lt 2) {
    throw "Expected dirty history rings before reset."
}
if ($postCommandHistoryLen -ne 1 -or $postCommandHistoryFirstSeq -ne 13 -or $postCommandHistoryFirstOpcode -ne 3) {
    throw "Command history did not collapse to the reset receipt as expected."
}
if ($postHealthHistoryLen -ne 1 -or $postHealthHistoryFirstCode -ne 200 -or $postHealthHistoryFirstAck -ne 13) {
    throw "Health history did not collapse to the reset receipt as expected."
}
if ($postModeHistoryLen -ne 0 -or $postBootHistoryLen -ne 0) {
    throw "Mode/boot histories were not cleared by reset-counters."
}

Write-Output "__NAME__=pass"
Write-Output "POST_COMMAND_HISTORY_LEN=$postCommandHistoryLen"
Write-Output "POST_COMMAND_HISTORY_FIRST_SEQ=$postCommandHistoryFirstSeq"
Write-Output "POST_HEALTH_HISTORY_LEN=$postHealthHistoryLen"
Write-Output "POST_HEALTH_HISTORY_FIRST_ACK=$postHealthHistoryFirstAck"
