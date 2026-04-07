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
    -SkippedReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_SELECTIVE_REASON_DRAIN_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_SELECTIVE_REASON_DRAIN_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-wake-queue-selective-probe-check.ps1' `
    -FailureLabel 'wake-queue selective'
$probeText = $probeState.Text


$postReasonLen = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SELECTIVE_PROBE_POST_REASON_LEN'
$postReasonTask1 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SELECTIVE_PROBE_POST_REASON_TASK1'
if ($null -in @($postReasonLen,$postReasonTask1)) {
    throw 'Missing expected reason-drain fields in wake-queue selective probe output.'
}
if ($postReasonLen -ne 4) { throw "Expected POST_REASON_LEN=4. got $postReasonLen" }
if ($postReasonTask1 -ne 3) { throw "Expected POST_REASON_TASK1=3. got $postReasonTask1" }

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_SELECTIVE_REASON_DRAIN_PROBE=pass'
Write-Output "POST_REASON_LEN=$postReasonLen"
Write-Output "POST_REASON_TASK1=$postReasonTask1"
