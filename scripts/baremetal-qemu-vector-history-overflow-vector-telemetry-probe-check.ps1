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
    -SkippedReceipt 'BAREMETAL_QEMU_VECTOR_HISTORY_OVERFLOW_VECTOR_TELEMETRY_PROBE' `
    -FailureLabel 'vector-history-overflow' `
    -EchoOnSuccess:$true `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true
$probeText = $probeState.Text

$interruptCount = Extract-IntValue -Text $probeText -Name 'INTERRUPT_COUNT_PHASE_B'
$interruptVectorCount = Extract-IntValue -Text $probeText -Name 'INTERRUPT_VECTOR_13_COUNT_PHASE_B'
$exceptionVectorCount = Extract-IntValue -Text $probeText -Name 'EXCEPTION_VECTOR_13_COUNT_PHASE_B'
$interruptLastVector = Extract-IntValue -Text $probeText -Name 'LAST_INTERRUPT_VECTOR_PHASE_B'
$exceptionLastVector = Extract-IntValue -Text $probeText -Name 'LAST_EXCEPTION_VECTOR_PHASE_B'
$lastExceptionCode = Extract-IntValue -Text $probeText -Name 'LAST_EXCEPTION_CODE_PHASE_B'

if ($null -in @($interruptCount, $interruptVectorCount, $exceptionVectorCount, $interruptLastVector, $exceptionLastVector, $lastExceptionCode)) {
    throw 'Missing phase B vector-telemetry fields.'
}
if ($interruptCount -ne 19) { throw "Expected INTERRUPT_COUNT_PHASE_B=19. got $interruptCount" }
if ($interruptVectorCount -ne 19) { throw "Expected INTERRUPT_VECTOR_13_COUNT_PHASE_B=19. got $interruptVectorCount" }
if ($exceptionVectorCount -ne 19) { throw "Expected EXCEPTION_VECTOR_13_COUNT_PHASE_B=19. got $exceptionVectorCount" }
if ($interruptLastVector -ne 13) { throw "Expected LAST_INTERRUPT_VECTOR_PHASE_B=13. got $interruptLastVector" }
if ($exceptionLastVector -ne 13) { throw "Expected LAST_EXCEPTION_VECTOR_PHASE_B=13. got $exceptionLastVector" }
if ($lastExceptionCode -ne 118) { throw "Expected LAST_EXCEPTION_CODE_PHASE_B=118. got $lastExceptionCode" }

Write-Output 'BAREMETAL_QEMU_VECTOR_HISTORY_OVERFLOW_VECTOR_TELEMETRY_PROBE=pass'
Write-Output "INTERRUPT_COUNT_PHASE_B=$interruptCount"
Write-Output "INTERRUPT_VECTOR_13_COUNT_PHASE_B=$interruptVectorCount"
Write-Output "EXCEPTION_VECTOR_13_COUNT_PHASE_B=$exceptionVectorCount"
Write-Output "LAST_INTERRUPT_VECTOR_PHASE_B=$interruptLastVector"
Write-Output "LAST_EXCEPTION_VECTOR_PHASE_B=$exceptionLastVector"
Write-Output "LAST_EXCEPTION_CODE_PHASE_B=$lastExceptionCode"
