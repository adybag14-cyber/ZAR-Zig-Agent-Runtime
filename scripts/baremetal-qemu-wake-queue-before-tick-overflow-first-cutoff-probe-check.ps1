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
    -SkippedReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_OVERFLOW_FIRST_CUTOFF_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_OVERFLOW_FIRST_CUTOFF_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-wake-queue-before-tick-overflow-probe-check.ps1' `
    -FailureLabel 'wake-queue before-tick overflow' `
    -InvokeArgs $invoke
$probeText = $probeState.Text


$preFirstSeq = Extract-IntValue -Text $probeText -Name 'PRE_FIRST_SEQ'
$preCutoffSeq = Extract-IntValue -Text $probeText -Name 'PRE_CUTOFF_SEQ'
$preLastSeq = Extract-IntValue -Text $probeText -Name 'PRE_LAST_SEQ'
$postFirstCount = Extract-IntValue -Text $probeText -Name 'POST_FIRST_COUNT'
$postFirstSeq = Extract-IntValue -Text $probeText -Name 'POST_FIRST_SEQ'

if ($null -in @($preFirstSeq, $preCutoffSeq, $preLastSeq, $postFirstCount, $postFirstSeq)) {
    throw 'Missing expected first-cutoff fields in wake-queue before-tick overflow probe output.'
}
if ($preFirstSeq -ne 3) { throw "Expected PRE_FIRST_SEQ=3. got $preFirstSeq" }
if ($preCutoffSeq -ne 34) { throw "Expected PRE_CUTOFF_SEQ=34. got $preCutoffSeq" }
if ($preLastSeq -ne 66) { throw "Expected PRE_LAST_SEQ=66. got $preLastSeq" }
if ($postFirstCount -ne 32) { throw "Expected POST_FIRST_COUNT=32. got $postFirstCount" }
if ($postFirstSeq -ne 35) { throw "Expected POST_FIRST_SEQ=35. got $postFirstSeq" }

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_OVERFLOW_FIRST_CUTOFF_PROBE=pass'
Write-Output "PRE_FIRST_SEQ=$preFirstSeq"
Write-Output "PRE_CUTOFF_SEQ=$preCutoffSeq"
Write-Output "PRE_LAST_SEQ=$preLastSeq"
Write-Output "POST_FIRST_COUNT=$postFirstCount"
Write-Output "POST_FIRST_SEQ=$postFirstSeq"
