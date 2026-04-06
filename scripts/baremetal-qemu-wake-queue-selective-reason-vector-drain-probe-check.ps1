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
    -SkippedReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_SELECTIVE_REASON_VECTOR_DRAIN_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_SELECTIVE_REASON_VECTOR_DRAIN_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-wake-queue-selective-probe-check.ps1' `
    -FailureLabel 'wake-queue selective'
$probeText = $probeState.Text


$preReasonVectorCount31 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SELECTIVE_PROBE_PRE_REASON_VECTOR_COUNT_INTERRUPT_31'
$postReasonVectorLen = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SELECTIVE_PROBE_POST_REASON_VECTOR_LEN'
$postReasonVectorTask0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SELECTIVE_PROBE_POST_REASON_VECTOR_TASK0'
$postReasonVectorTask1 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SELECTIVE_PROBE_POST_REASON_VECTOR_TASK1'
$postReasonVectorCount31 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SELECTIVE_PROBE_POST_REASON_VECTOR_COUNT_INTERRUPT_31'
if ($null -in @($preReasonVectorCount31,$postReasonVectorLen,$postReasonVectorTask0,$postReasonVectorTask1,$postReasonVectorCount31)) {
    throw 'Missing expected reason-vector drain fields in wake-queue selective probe output.'
}
if ($preReasonVectorCount31 -ne 1) { throw "Expected PRE_REASON_VECTOR_COUNT_INTERRUPT_31=1. got $preReasonVectorCount31" }
if ($postReasonVectorLen -ne 2) { throw "Expected POST_REASON_VECTOR_LEN=2. got $postReasonVectorLen" }
if ($postReasonVectorTask0 -ne 1 -or $postReasonVectorTask1 -ne 5) {
    throw "Unexpected post-reason-vector task ordering: $postReasonVectorTask0,$postReasonVectorTask1"
}
if ($postReasonVectorCount31 -ne 0) { throw "Expected POST_REASON_VECTOR_COUNT_INTERRUPT_31=0. got $postReasonVectorCount31" }

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_SELECTIVE_REASON_VECTOR_DRAIN_PROBE=pass'
Write-Output "PRE_REASON_VECTOR_COUNT_INTERRUPT_31=$preReasonVectorCount31"
Write-Output "POST_REASON_VECTOR_LEN=$postReasonVectorLen"
Write-Output "POST_REASON_VECTOR_TASK0=$postReasonVectorTask0"
Write-Output "POST_REASON_VECTOR_TASK1=$postReasonVectorTask1"
Write-Output "POST_REASON_VECTOR_COUNT_INTERRUPT_31=$postReasonVectorCount31"
