# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-vector-history-overflow-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_VECTOR_HISTORY_OVERFLOW_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_VECTOR_HISTORY_OVERFLOW_INTERRUPT_OVERFLOW_PROBE' `
    -FailureLabel 'vector-history-overflow' `
    -EchoOnSuccess:$true `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true
$probeText = $probeState.Text

$count = Extract-IntValue -Text $probeText -Name 'INTERRUPT_COUNT_PHASE_A'
$vectorCount = Extract-IntValue -Text $probeText -Name 'INTERRUPT_VECTOR_200_COUNT_PHASE_A'
$historyLen = Extract-IntValue -Text $probeText -Name 'INTERRUPT_HISTORY_LEN_PHASE_A'
$overflow = Extract-IntValue -Text $probeText -Name 'INTERRUPT_HISTORY_OVERFLOW_PHASE_A'

if ($null -in @($count, $vectorCount, $historyLen, $overflow)) {
    throw 'Missing phase A interrupt-overflow fields.'
}
if ($count -ne 35) { throw "Expected INTERRUPT_COUNT_PHASE_A=35. got $count" }
if ($vectorCount -ne 35) { throw "Expected INTERRUPT_VECTOR_200_COUNT_PHASE_A=35. got $vectorCount" }
if ($historyLen -ne 32) { throw "Expected INTERRUPT_HISTORY_LEN_PHASE_A=32. got $historyLen" }
if ($overflow -ne 3) { throw "Expected INTERRUPT_HISTORY_OVERFLOW_PHASE_A=3. got $overflow" }

Write-Output 'BAREMETAL_QEMU_VECTOR_HISTORY_OVERFLOW_INTERRUPT_OVERFLOW_PROBE=pass'
Write-Output "INTERRUPT_COUNT_PHASE_A=$count"
Write-Output "INTERRUPT_VECTOR_200_COUNT_PHASE_A=$vectorCount"
Write-Output "INTERRUPT_HISTORY_LEN_PHASE_A=$historyLen"
Write-Output "INTERRUPT_HISTORY_OVERFLOW_PHASE_A=$overflow"
