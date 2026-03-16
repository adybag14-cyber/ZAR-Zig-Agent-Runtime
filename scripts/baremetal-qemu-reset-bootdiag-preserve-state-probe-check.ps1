# SPDX-License-Identifier: GPL-2.0-only
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
    Write-Output "BAREMETAL_QEMU_RESET_BOOTDIAG_PRESERVE_STATE_PROBE=skipped"
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying bootdiag/history-clear probe failed with exit code $probeExitCode"
}

$preResetStack = Extract-IntValue -Text $probeText -Name "PRE_RESET_STACK"
$cmdHistoryLen = Extract-IntValue -Text $probeText -Name "CMD_HISTORY_LEN"
$bootHistoryLen = Extract-IntValue -Text $probeText -Name "BOOT_HISTORY_LEN"
$bootdiagBootSeq = Extract-IntValue -Text $probeText -Name "BOOTDIAG_BOOT_SEQ"
$statusModeReset = Extract-IntValue -Text $probeText -Name "STATUS_MODE_RESET"
$bootdiagPhase = Extract-IntValue -Text $probeText -Name "BOOTDIAG_PHASE"

if ($null -eq $preResetStack -or
    $null -eq $cmdHistoryLen -or
    $null -eq $bootHistoryLen -or
    $null -eq $bootdiagBootSeq -or
    $null -eq $statusModeReset -or
    $null -eq $bootdiagPhase) {
    throw "Missing expected bootdiag preservation fields in probe output."
}
if ($preResetStack -le 0) {
    throw "Expected PRE_RESET_STACK to be non-zero before reset. got $preResetStack"
}
if ($cmdHistoryLen -ne 4) {
    throw "Expected command history to remain intact across command_reset_boot_diagnostics. got len=$cmdHistoryLen"
}
if ($bootHistoryLen -ne 3) {
    throw "Expected boot-phase history to remain intact across command_reset_boot_diagnostics. got len=$bootHistoryLen"
}
if ($bootdiagBootSeq -ne 1) {
    throw "Expected boot diagnostics boot sequence to restart at 1 after reset. got $bootdiagBootSeq"
}
if ($statusModeReset -ne 1) {
    throw "Expected runtime mode to stay running across command_reset_boot_diagnostics. got mode=$statusModeReset"
}
if ($bootdiagPhase -ne 2) {
    throw "Expected boot diagnostics phase to reset to runtime. got phase=$bootdiagPhase"
}

Write-Output "BAREMETAL_QEMU_RESET_BOOTDIAG_PRESERVE_STATE_PROBE=pass"
Write-Output "PRE_RESET_STACK=$preResetStack"
Write-Output "CMD_HISTORY_LEN=$cmdHistoryLen"
Write-Output "BOOT_HISTORY_LEN=$bootHistoryLen"
Write-Output "BOOTDIAG_BOOT_SEQ=$bootdiagBootSeq"
Write-Output "STATUS_MODE_RESET=$statusModeReset"
Write-Output "BOOTDIAG_PHASE=$bootdiagPhase"
