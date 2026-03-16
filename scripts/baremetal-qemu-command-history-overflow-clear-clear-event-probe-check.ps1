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
    Write-Output 'BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_CLEAR_EVENT_PROBE=skipped'
    Write-Output 'BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_CLEAR_EVENT_PROBE_SOURCE=baremetal-qemu-command-history-overflow-clear-probe-check.ps1'
    exit 0
}
if ($exitCode -ne 0) {
    if ($outputText) { Write-Output $outputText.TrimEnd() }
    throw "Command-history overflow/clear prerequisite probe failed with exit code $exitCode"
}

$clearLen = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_PROBE_CLEAR_LEN'
$clearFirstSeq = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_PROBE_CLEAR_FIRST_SEQ'
$clearFirstOpcode = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_PROBE_CLEAR_FIRST_OPCODE'
$clearFirstResult = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_PROBE_CLEAR_FIRST_RESULT'
$healthPreserveLen = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_PROBE_HEALTH_PRESERVE_LEN'
if ($clearLen -ne 1 -or $clearFirstSeq -ne 5 -or $clearFirstOpcode -ne 19 -or $clearFirstResult -ne 0 -or $healthPreserveLen -ne 6) {
    throw "Unexpected clear-event state. clearLen=$clearLen clearFirstSeq=$clearFirstSeq clearFirstOpcode=$clearFirstOpcode clearFirstResult=$clearFirstResult healthPreserveLen=$healthPreserveLen"
}

Write-Output 'BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_CLEAR_EVENT_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_CLEAR_EVENT_PROBE_SOURCE=baremetal-qemu-command-history-overflow-clear-probe-check.ps1'
Write-Output "CLEAR_LEN=$clearLen"
Write-Output "CLEAR_FIRST_SEQ=$clearFirstSeq"
Write-Output "CLEAR_FIRST_OPCODE=$clearFirstOpcode"
Write-Output "CLEAR_FIRST_RESULT=$clearFirstResult"
Write-Output "HEALTH_PRESERVE_LEN=$healthPreserveLen"

