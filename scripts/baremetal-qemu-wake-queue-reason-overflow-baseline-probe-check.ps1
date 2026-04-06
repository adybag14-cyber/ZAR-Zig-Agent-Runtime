# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-wake-queue-reason-overflow-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$invoke = @{ TimeoutSeconds = 90 }
$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_WAKE_QUEUE_REASON_OVERFLOW_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_OVERFLOW_BASELINE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_OVERFLOW_BASELINE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-wake-queue-reason-overflow-probe-check.ps1' `
    -FailureLabel 'wake-queue reason-overflow' `
    -InvokeArgs $invoke
$probeText = $probeState.Text


$wakeCycles = Extract-IntValue -Text $probeText -Name 'WAKE_CYCLES'
$taskId = Extract-IntValue -Text $probeText -Name 'TASK_ID'
$preCount = Extract-IntValue -Text $probeText -Name 'PRE_COUNT'
$preHead = Extract-IntValue -Text $probeText -Name 'PRE_HEAD'
$preTail = Extract-IntValue -Text $probeText -Name 'PRE_TAIL'
$preOverflow = Extract-IntValue -Text $probeText -Name 'PRE_OVERFLOW'
$preFirstSeq = Extract-IntValue -Text $probeText -Name 'PRE_FIRST_SEQ'
$preFirstReason = Extract-IntValue -Text $probeText -Name 'PRE_FIRST_REASON'
$preLastSeq = Extract-IntValue -Text $probeText -Name 'PRE_LAST_SEQ'
$preLastReason = Extract-IntValue -Text $probeText -Name 'PRE_LAST_REASON'

if ($null -in @($wakeCycles, $taskId, $preCount, $preHead, $preTail, $preOverflow, $preFirstSeq, $preFirstReason, $preLastSeq, $preLastReason)) {
    throw 'Missing expected baseline fields in wake-queue-reason-overflow probe output.'
}
if ($wakeCycles -ne 66) { throw "Expected WAKE_CYCLES=66. got $wakeCycles" }
if ($taskId -le 0) { throw "Expected TASK_ID > 0. got $taskId" }
if ($preCount -ne 64 -or $preHead -ne 2 -or $preTail -ne 2 -or $preOverflow -ne 2) {
    throw "Unexpected PRE queue summary: $preCount/$preHead/$preTail/$preOverflow"
}
if ($preFirstSeq -ne 3 -or $preFirstReason -ne 3 -or $preLastSeq -ne 66 -or $preLastReason -ne 2) {
    throw "Unexpected PRE seq/reason summary: $preFirstSeq/$preFirstReason/$preLastSeq/$preLastReason"
}

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_OVERFLOW_BASELINE_PROBE=pass'
Write-Output "WAKE_CYCLES=$wakeCycles"
Write-Output "TASK_ID=$taskId"
Write-Output "PRE_COUNT=$preCount"
Write-Output "PRE_HEAD=$preHead"
Write-Output "PRE_TAIL=$preTail"
Write-Output "PRE_OVERFLOW=$preOverflow"
Write-Output "PRE_FIRST_SEQ=$preFirstSeq"
Write-Output "PRE_FIRST_REASON=$preFirstReason"
Write-Output "PRE_LAST_SEQ=$preLastSeq"
Write-Output "PRE_LAST_REASON=$preLastReason"
