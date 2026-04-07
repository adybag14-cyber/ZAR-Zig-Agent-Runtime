# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-wake-queue-clear-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$invoke = @{ TimeoutSeconds = 90 }
$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_WAKE_QUEUE_CLEAR_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_CLEAR_COLLAPSE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_CLEAR_COLLAPSE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-wake-queue-clear-probe-check.ps1' `
    -FailureLabel 'wake-queue clear' `
    -InvokeArgs $invoke
$probeText = $probeState.Text


$postClearCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_CLEAR_POST_CLEAR_COUNT'
$postClearHead = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_CLEAR_POST_CLEAR_HEAD'
$postClearTail = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_CLEAR_POST_CLEAR_TAIL'
$postClearOverflow = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_CLEAR_POST_CLEAR_OVERFLOW'

if ($null -in @($postClearCount, $postClearHead, $postClearTail, $postClearOverflow)) {
    throw 'Missing expected post-clear collapse fields in wake-queue-clear probe output.'
}
if ($postClearCount -ne 0 -or $postClearHead -ne 0 -or $postClearTail -ne 0 -or $postClearOverflow -ne 0) {
    throw "Unexpected POST_CLEAR collapse: $postClearCount/$postClearHead/$postClearTail/$postClearOverflow"
}

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_CLEAR_COLLAPSE_PROBE=pass'
Write-Output "POST_CLEAR_COUNT=$postClearCount"
Write-Output "POST_CLEAR_HEAD=$postClearHead"
Write-Output "POST_CLEAR_TAIL=$postClearTail"
Write-Output "POST_CLEAR_OVERFLOW=$postClearOverflow"
