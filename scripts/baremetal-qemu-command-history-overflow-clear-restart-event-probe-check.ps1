# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 90
)

$ErrorActionPreference = 'Stop'
$probe = Join-Path $PSScriptRoot 'baremetal-qemu-command-history-overflow-clear-probe-check.ps1'
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $match = [regex]::Match($Text, '(?m)^' + [regex]::Escape($Name) + '=(-?\d+)\r?$')
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$invoke = @{ TimeoutSeconds = $TimeoutSeconds }
if ($SkipBuild) { $invoke.SkipBuild = $true }

$output = & $probe @invoke 2>&1
$exitCode = $LASTEXITCODE
$outputText = ($output | Out-String)
if ($outputText -match '(?m)^BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_PROBE=skipped\r?$') {
    if ($outputText) { Write-Output $outputText.TrimEnd() }
    Write-Output 'BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_RESTART_EVENT_PROBE=skipped'
    Write-Output 'BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_RESTART_EVENT_PROBE_SOURCE=baremetal-qemu-command-history-overflow-clear-probe-check.ps1'
    exit 0
}
if ($exitCode -ne 0) {
    if ($outputText) { Write-Output $outputText.TrimEnd() }
    throw "Command-history overflow/clear prerequisite probe failed with exit code $exitCode"
}

$restartLen = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_PROBE_RESTART_LEN'
$restartSeq = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_PROBE_RESTART_SEQ'
$restartOpcode = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_PROBE_RESTART_OPCODE'
$restartResult = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_PROBE_RESTART_RESULT'
$restartArg0 = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_PROBE_RESTART_ARG0'
if ($restartLen -ne 2 -or $restartSeq -ne 6 -or $restartOpcode -ne 20 -or $restartResult -ne 0 -or $restartArg0 -ne 0) {
    throw "Unexpected restart-event state. restartLen=$restartLen restartSeq=$restartSeq restartOpcode=$restartOpcode restartResult=$restartResult restartArg0=$restartArg0"
}

Write-Output 'BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_RESTART_EVENT_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_RESTART_EVENT_PROBE_SOURCE=baremetal-qemu-command-history-overflow-clear-probe-check.ps1'
Write-Output "RESTART_LEN=$restartLen"
Write-Output "RESTART_SEQ=$restartSeq"
Write-Output "RESTART_OPCODE=$restartOpcode"
Write-Output "RESTART_RESULT=$restartResult"
Write-Output "RESTART_ARG0=$restartArg0"
