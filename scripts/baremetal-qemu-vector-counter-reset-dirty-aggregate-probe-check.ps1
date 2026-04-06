# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-vector-counter-reset-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_VECTOR_COUNTER_RESET_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_VECTOR_COUNTER_RESET_DIRTY_AGGREGATE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_VECTOR_COUNTER_RESET_DIRTY_AGGREGATE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-vector-counter-reset-probe-check.ps1' `
    -FailureLabel 'vector-counter-reset'
$probeText = $probeState.Text


$preInterrupt = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_VECTOR_COUNTER_RESET_PRE_INTERRUPT_COUNT'
$preException = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_VECTOR_COUNTER_RESET_PRE_EXCEPTION_COUNT'
if ($null -in @($preInterrupt, $preException)) {
    throw 'Missing dirty aggregate fields in vector-counter-reset output.'
}
if ($preInterrupt -ne 4 -or $preException -ne 3) {
    throw "Unexpected dirty aggregate baseline. interrupt=$preInterrupt exception=$preException"
}

Write-Output 'BAREMETAL_QEMU_VECTOR_COUNTER_RESET_DIRTY_AGGREGATE_PROBE=pass'
Write-Output "PRE_INTERRUPT_COUNT=$preInterrupt"
Write-Output "PRE_EXCEPTION_COUNT=$preException"
