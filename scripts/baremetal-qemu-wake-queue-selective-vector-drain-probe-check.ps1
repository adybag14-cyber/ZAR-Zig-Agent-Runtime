# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-wake-queue-selective-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_WAKE_QUEUE_SELECTIVE_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_SELECTIVE_VECTOR_DRAIN_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_SELECTIVE_VECTOR_DRAIN_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-wake-queue-selective-probe-check.ps1' `
    -FailureLabel 'wake-queue selective'
$probeText = $probeState.Text


$postVectorLen = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SELECTIVE_PROBE_POST_VECTOR_LEN'
$postVectorTask1 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SELECTIVE_PROBE_POST_VECTOR_TASK1'
$postVectorCount13 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SELECTIVE_PROBE_POST_VECTOR_COUNT_13'
$postVectorCount31 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SELECTIVE_PROBE_POST_VECTOR_COUNT_31'
if ($null -in @($postVectorLen,$postVectorTask1,$postVectorCount13,$postVectorCount31)) {
    throw 'Missing expected vector-drain fields in wake-queue selective probe output.'
}
if ($postVectorLen -ne 3) { throw "Expected POST_VECTOR_LEN=3. got $postVectorLen" }
if ($postVectorTask1 -ne 4) { throw "Expected POST_VECTOR_TASK1=4. got $postVectorTask1" }
if ($postVectorCount13 -ne 0 -or $postVectorCount31 -ne 1) {
    throw "Unexpected post-vector counts: 13=$postVectorCount13 31=$postVectorCount31"
}

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_SELECTIVE_VECTOR_DRAIN_PROBE=pass'
Write-Output "POST_VECTOR_LEN=$postVectorLen"
Write-Output "POST_VECTOR_TASK1=$postVectorTask1"
Write-Output "POST_VECTOR_COUNT_13=$postVectorCount13"
Write-Output "POST_VECTOR_COUNT_31=$postVectorCount31"
