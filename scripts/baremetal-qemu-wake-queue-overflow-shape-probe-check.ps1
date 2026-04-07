# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-wake-queue-overflow-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$invoke = @{ TimeoutSeconds = 90 }
$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_SHAPE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_SHAPE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-wake-queue-overflow-probe-check.ps1' `
    -FailureLabel 'wake-queue overflow' `
    -InvokeArgs $invoke
$probeText = $probeState.Text


$count = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_COUNT'
$head = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_HEAD'
$tail = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_TAIL'
$overflow = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_OVERFLOW'

if ($null -in @($count, $head, $tail, $overflow)) {
    throw 'Missing expected shape fields in wake-queue-overflow probe output.'
}
if ($count -ne 64) { throw "Expected COUNT=64. got $count" }
if ($head -ne 2) { throw "Expected HEAD=2. got $head" }
if ($tail -ne 2) { throw "Expected TAIL=2. got $tail" }
if ($overflow -ne 2) { throw "Expected OVERFLOW=2. got $overflow" }

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_SHAPE_PROBE=pass'
Write-Output "COUNT=$count"
Write-Output "HEAD=$head"
Write-Output "TAIL=$tail"
Write-Output "OVERFLOW=$overflow"
