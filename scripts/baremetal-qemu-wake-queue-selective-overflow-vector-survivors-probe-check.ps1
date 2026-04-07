# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-wake-queue-selective-overflow-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$invoke = @{ TimeoutSeconds = 90 }
$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_WAKE_QUEUE_SELECTIVE_OVERFLOW_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_SELECTIVE_OVERFLOW_VECTOR_SURVIVORS_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_SELECTIVE_OVERFLOW_VECTOR_SURVIVORS_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-wake-queue-selective-overflow-probe-check.ps1' `
    -FailureLabel 'wake-queue selective overflow' `
    -InvokeArgs $invoke
$probeText = $probeState.Text


$firstSeq = Extract-IntValue -Text $probeText -Name 'POST_VECTOR_FIRST_SEQ'
$firstVector = Extract-IntValue -Text $probeText -Name 'POST_VECTOR_FIRST_VECTOR'
$retainedSeq = Extract-IntValue -Text $probeText -Name 'POST_VECTOR_REMAINING_SEQ'
$retainedVector = Extract-IntValue -Text $probeText -Name 'POST_VECTOR_REMAINING_VECTOR'
$lastSeq = Extract-IntValue -Text $probeText -Name 'POST_VECTOR_LAST_SEQ'
$lastVector = Extract-IntValue -Text $probeText -Name 'POST_VECTOR_LAST_VECTOR'

if ($null -in @($firstSeq, $firstVector, $retainedSeq, $retainedVector, $lastSeq, $lastVector)) {
    throw 'Missing expected post-vector survivor fields in wake-queue-selective-overflow probe output.'
}
if ($firstSeq -ne 4 -or $firstVector -ne 31 -or $retainedSeq -ne 65 -or $retainedVector -ne 13 -or $lastSeq -ne 66 -or $lastVector -ne 31) {
    throw 'Unexpected POST_VECTOR survivor ordering.'
}

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_SELECTIVE_OVERFLOW_VECTOR_SURVIVORS_PROBE=pass'
Write-Output "POST_VECTOR_FIRST_SEQ=$firstSeq"
Write-Output "POST_VECTOR_FIRST_VECTOR=$firstVector"
Write-Output "POST_VECTOR_REMAINING_SEQ=$retainedSeq"
Write-Output "POST_VECTOR_REMAINING_VECTOR=$retainedVector"
Write-Output "POST_VECTOR_LAST_SEQ=$lastSeq"
Write-Output "POST_VECTOR_LAST_VECTOR=$lastVector"
