param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-bootdiag-history-clear-probe-check.ps1"

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
if ($probeText -match 'BAREMETAL_QEMU_BOOTDIAG_HISTORY_CLEAR_PROBE=skipped') {
    Write-Output "BAREMETAL_QEMU_CLEAR_COMMAND_HISTORY_PRESERVE_HEALTH_PROBE=skipped"
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying bootdiag/history-clear probe failed with exit code $probeExitCode"
}

$ack2 = Extract-IntValue -Text $probeText -Name "ACK2"
$cmdHistoryLen2 = Extract-IntValue -Text $probeText -Name "CMD_HISTORY_LEN2"
$healthHistoryLen2 = Extract-IntValue -Text $probeText -Name "HEALTH_HISTORY_LEN2"
$cmdHistoryFirstOpcode = Extract-IntValue -Text $probeText -Name "CMD_HISTORY_FIRST_OPCODE"

if ($null -eq $ack2 -or
    $null -eq $cmdHistoryLen2 -or
    $null -eq $healthHistoryLen2 -or
    $null -eq $cmdHistoryFirstOpcode) {
    throw "Missing expected clear-command-history preservation fields in probe output."
}
if ($ack2 -ne 5) {
    throw "Expected ACK2=5 after command_clear_command_history. got $ack2"
}
if ($cmdHistoryLen2 -ne 1) {
    throw "Expected command history to collapse to one clear receipt. got len=$cmdHistoryLen2"
}
if ($healthHistoryLen2 -ne 6) {
    throw "Expected health history to remain intact after command_clear_command_history. got len=$healthHistoryLen2"
}
if ($cmdHistoryFirstOpcode -ne 19) {
    throw "Expected first command-history opcode after clear to be 19. got $cmdHistoryFirstOpcode"
}

Write-Output "BAREMETAL_QEMU_CLEAR_COMMAND_HISTORY_PRESERVE_HEALTH_PROBE=pass"
Write-Output "ACK2=$ack2"
Write-Output "CMD_HISTORY_LEN2=$cmdHistoryLen2"
Write-Output "HEALTH_HISTORY_LEN2=$healthHistoryLen2"
Write-Output "CMD_HISTORY_FIRST_OPCODE=$cmdHistoryFirstOpcode"
