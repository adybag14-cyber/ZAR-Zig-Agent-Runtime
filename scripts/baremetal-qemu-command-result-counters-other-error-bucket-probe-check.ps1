# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-command-result-counters-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_COMMAND_RESULT_COUNTERS_PROBE=skipped\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_COMMAND_RESULT_COUNTERS_OTHER_ERROR_BUCKET_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_COMMAND_RESULT_COUNTERS_OTHER_ERROR_BUCKET_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-command-result-counters-probe-check.ps1' `
    -FailureLabel 'command-result counters'
$probeText = $probeState.Text

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
