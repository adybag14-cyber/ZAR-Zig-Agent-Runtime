# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-wake-queue-before-tick-overflow-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$invoke = @{ TimeoutSeconds = 90 }
$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_OVERFLOW_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_OVERFLOW_SECOND_CUTOFF_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_OVERFLOW_SECOND_CUTOFF_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-wake-queue-before-tick-overflow-probe-check.ps1' `
    -FailureLabel 'wake-queue before-tick overflow' `
    -InvokeArgs $invoke
$probeText = $probeState.Text


$postSecondCount = Extract-IntValue -Text $probeText -Name 'POST_SECOND_COUNT'
$postSecondHead = Extract-IntValue -Text $probeText -Name 'POST_SECOND_HEAD'
$postSecondTail = Extract-IntValue -Text $probeText -Name 'POST_SECOND_TAIL'
$postSecondOverflow = Extract-IntValue -Text $probeText -Name 'POST_SECOND_OVERFLOW'
$postSecondSeq = Extract-IntValue -Text $probeText -Name 'POST_SECOND_SEQ'

if ($null -in @($postSecondCount, $postSecondHead, $postSecondTail, $postSecondOverflow, $postSecondSeq)) {
    throw 'Missing expected second-cutoff fields in wake-queue before-tick overflow probe output.'
}
if ($postSecondCount -ne 1) { throw "Expected POST_SECOND_COUNT=1. got $postSecondCount" }
if ($postSecondHead -ne 1) { throw "Expected POST_SECOND_HEAD=1. got $postSecondHead" }
if ($postSecondTail -ne 0) { throw "Expected POST_SECOND_TAIL=0. got $postSecondTail" }
if ($postSecondOverflow -ne 2) { throw "Expected POST_SECOND_OVERFLOW=2. got $postSecondOverflow" }
if ($postSecondSeq -ne 66) { throw "Expected POST_SECOND_SEQ=66. got $postSecondSeq" }

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_OVERFLOW_SECOND_CUTOFF_PROBE=pass'
Write-Output "POST_SECOND_COUNT=$postSecondCount"
Write-Output "POST_SECOND_HEAD=$postSecondHead"
Write-Output "POST_SECOND_TAIL=$postSecondTail"
Write-Output "POST_SECOND_OVERFLOW=$postSecondOverflow"
Write-Output "POST_SECOND_SEQ=$postSecondSeq"
