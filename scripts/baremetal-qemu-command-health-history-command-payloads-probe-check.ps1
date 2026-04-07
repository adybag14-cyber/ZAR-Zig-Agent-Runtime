# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-command-health-history-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe -ProbePath $probe -SkipBuild:$SkipBuild -SkippedPattern '(?m)^BAREMETAL_QEMU_COMMAND_HEALTH_HISTORY_PROBE=skipped\r?$' -SkippedReceipt 'BAREMETAL_QEMU_COMMAND_HEALTH_HISTORY_COMMAND_PAYLOADS_PROBE' -SkippedSourceReceipt 'BAREMETAL_QEMU_COMMAND_HEALTH_HISTORY_COMMAND_PAYLOADS_PROBE_SOURCE' -SkippedSourceValue 'baremetal-qemu-command-health-history-probe-check.ps1' -FailureLabel 'command-health history'
$probeText = $probeState.Text
firstSeq = Extract-IntValue -Text $probeText -Name 'COMMAND_HISTORY_FIRST_SEQ'
$firstArg0 = Extract-IntValue -Text $probeText -Name 'COMMAND_HISTORY_FIRST_ARG0'
$lastSeq = Extract-IntValue -Text $probeText -Name 'COMMAND_HISTORY_LAST_SEQ'
$lastArg0 = Extract-IntValue -Text $probeText -Name 'COMMAND_HISTORY_LAST_ARG0'

if ($null -in @($firstSeq, $firstArg0, $lastSeq, $lastArg0)) {
    throw 'Missing command-history payload fields.'
}
if ($firstSeq -ne 4) { throw "Expected COMMAND_HISTORY_FIRST_SEQ=4. got $firstSeq" }
if ($firstArg0 -ne 103) { throw "Expected COMMAND_HISTORY_FIRST_ARG0=103. got $firstArg0" }
if ($lastSeq -ne 35) { throw "Expected COMMAND_HISTORY_LAST_SEQ=35. got $lastSeq" }
if ($lastArg0 -ne 134) { throw "Expected COMMAND_HISTORY_LAST_ARG0=134. got $lastArg0" }

Write-Output 'BAREMETAL_QEMU_COMMAND_HEALTH_HISTORY_COMMAND_PAYLOADS_PROBE=pass'
Write-Output "COMMAND_HISTORY_FIRST_SEQ=$firstSeq"
Write-Output "COMMAND_HISTORY_FIRST_ARG0=$firstArg0"
Write-Output "COMMAND_HISTORY_LAST_SEQ=$lastSeq"
Write-Output "COMMAND_HISTORY_LAST_ARG0=$lastArg0"
