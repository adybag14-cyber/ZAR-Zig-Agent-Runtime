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
    -SkippedReceipt 'BAREMETAL_QEMU_COMMAND_RESULT_COUNTERS_OK_BUCKET_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_COMMAND_RESULT_COUNTERS_OK_BUCKET_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-command-result-counters-probe-check.ps1' `
    -FailureLabel 'command-result counters'
$probeText = $probeState.Text

$preCounterOk = Extract-IntValue -Text $probeText -Name 'PRE_COUNTER_OK'
$preCounterTotal = Extract-IntValue -Text $probeText -Name 'PRE_COUNTER_TOTAL'
$preHealthCode = Extract-IntValue -Text $probeText -Name 'PRE_HEALTH_CODE'

if ($null -in @($preCounterOk, $preCounterTotal, $preHealthCode)) {
    throw 'Missing ok-bucket command-result fields.'
}
if ($preCounterOk -ne 1) { throw "Expected PRE_COUNTER_OK=1. got $preCounterOk" }
if ($preCounterTotal -ne 4) { throw "Expected PRE_COUNTER_TOTAL=4. got $preCounterTotal" }
if ($preHealthCode -ne 200) { throw "Expected PRE_HEALTH_CODE=200. got $preHealthCode" }

Write-Output 'BAREMETAL_QEMU_COMMAND_RESULT_COUNTERS_OK_BUCKET_PROBE=pass'
Write-Output "PRE_COUNTER_OK=$preCounterOk"
Write-Output "PRE_COUNTER_TOTAL=$preCounterTotal"
Write-Output "PRE_HEALTH_CODE=$preHealthCode"
