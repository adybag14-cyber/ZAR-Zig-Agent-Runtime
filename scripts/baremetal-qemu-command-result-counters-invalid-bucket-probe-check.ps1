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
    -SkippedReceipt 'BAREMETAL_QEMU_COMMAND_RESULT_COUNTERS_INVALID_BUCKET_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_COMMAND_RESULT_COUNTERS_INVALID_BUCKET_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-command-result-counters-probe-check.ps1' `
    -FailureLabel 'command-result counters'
$probeText = $probeState.Text

$preCounterInvalid = Extract-IntValue -Text $probeText -Name 'PRE_COUNTER_INVALID'
$preCounterTotal = Extract-IntValue -Text $probeText -Name 'PRE_COUNTER_TOTAL'
$preMode = Extract-IntValue -Text $probeText -Name 'PRE_MODE'

if ($null -in @($preCounterInvalid, $preCounterTotal, $preMode)) {
    throw 'Missing invalid-bucket command-result fields.'
}
if ($preCounterInvalid -ne 1) { throw "Expected PRE_COUNTER_INVALID=1. got $preCounterInvalid" }
if ($preCounterTotal -ne 4) { throw "Expected PRE_COUNTER_TOTAL=4. got $preCounterTotal" }
if ($preMode -ne 1) { throw "Expected PRE_MODE=1. got $preMode" }

Write-Output 'BAREMETAL_QEMU_COMMAND_RESULT_COUNTERS_INVALID_BUCKET_PROBE=pass'
Write-Output "PRE_COUNTER_INVALID=$preCounterInvalid"
Write-Output "PRE_COUNTER_TOTAL=$preCounterTotal"
Write-Output "PRE_MODE=$preMode"
