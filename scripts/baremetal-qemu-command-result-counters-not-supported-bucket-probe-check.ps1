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
    -SkippedReceipt 'BAREMETAL_QEMU_COMMAND_RESULT_COUNTERS_NOT_SUPPORTED_BUCKET_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_COMMAND_RESULT_COUNTERS_NOT_SUPPORTED_BUCKET_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-command-result-counters-probe-check.ps1' `
    -FailureLabel 'command-result counters'
$probeText = $probeState.Text

$preCounterNotSupported = Extract-IntValue -Text $probeText -Name 'PRE_COUNTER_NOT_SUPPORTED'
$preCounterTotal = Extract-IntValue -Text $probeText -Name 'PRE_COUNTER_TOTAL'
$preCounterLastSeq = Extract-IntValue -Text $probeText -Name 'PRE_COUNTER_LAST_SEQ'

if ($null -in @($preCounterNotSupported, $preCounterTotal, $preCounterLastSeq)) {
    throw 'Missing not-supported command-result fields.'
}
if ($preCounterNotSupported -ne 1) { throw "Expected PRE_COUNTER_NOT_SUPPORTED=1. got $preCounterNotSupported" }
if ($preCounterTotal -ne 4) { throw "Expected PRE_COUNTER_TOTAL=4. got $preCounterTotal" }
if ($preCounterLastSeq -ne 5) { throw "Expected PRE_COUNTER_LAST_SEQ=5. got $preCounterLastSeq" }

Write-Output 'BAREMETAL_QEMU_COMMAND_RESULT_COUNTERS_NOT_SUPPORTED_BUCKET_PROBE=pass'
Write-Output "PRE_COUNTER_NOT_SUPPORTED=$preCounterNotSupported"
Write-Output "PRE_COUNTER_TOTAL=$preCounterTotal"
Write-Output "PRE_COUNTER_LAST_SEQ=$preCounterLastSeq"
