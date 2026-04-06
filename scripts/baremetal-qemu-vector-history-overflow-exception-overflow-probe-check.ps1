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
    -SkippedReceipt 'BAREMETAL_QEMU_VECTOR_HISTORY_OVERFLOW_EXCEPTION_OVERFLOW_PROBE' `
    -FailureLabel 'vector-history-overflow' `
    -EchoOnSuccess:$true `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true
$probeText = $probeState.Text

$count = Extract-IntValue -Text $probeText -Name 'EXCEPTION_COUNT_PHASE_B'
$historyLen = Extract-IntValue -Text $probeText -Name 'EXCEPTION_HISTORY_LEN_PHASE_B'
$overflow = Extract-IntValue -Text $probeText -Name 'EXCEPTION_HISTORY_OVERFLOW_PHASE_B'

if ($null -in @($count, $historyLen, $overflow)) {
    throw 'Missing phase B exception-overflow fields.'
}
if ($count -ne 19) { throw "Expected EXCEPTION_COUNT_PHASE_B=19. got $count" }
if ($historyLen -ne 16) { throw "Expected EXCEPTION_HISTORY_LEN_PHASE_B=16. got $historyLen" }
if ($overflow -ne 3) { throw "Expected EXCEPTION_HISTORY_OVERFLOW_PHASE_B=3. got $overflow" }

Write-Output 'BAREMETAL_QEMU_VECTOR_HISTORY_OVERFLOW_EXCEPTION_OVERFLOW_PROBE=pass'
Write-Output "EXCEPTION_COUNT_PHASE_B=$count"
Write-Output "EXCEPTION_HISTORY_LEN_PHASE_B=$historyLen"
Write-Output "EXCEPTION_HISTORY_OVERFLOW_PHASE_B=$overflow"
