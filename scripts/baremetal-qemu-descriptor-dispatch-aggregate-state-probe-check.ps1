# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-descriptor-dispatch-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_AGGREGATE_STATE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_AGGREGATE_STATE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-descriptor-dispatch-probe-check.ps1' `
    -FailureLabel 'descriptor-dispatch'
$probeText = $probeState.Text


$lastInterruptVector = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_LAST_INTERRUPT_VECTOR'
$interruptCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_INTERRUPT_COUNT'
$lastExceptionVector = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_LAST_EXCEPTION_VECTOR'
$exceptionCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_EXCEPTION_COUNT'
$lastExceptionCode = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_LAST_EXCEPTION_CODE'
$interruptHistoryLen = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_INTERRUPT_HISTORY_LEN'
$exceptionHistoryLen = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_EXCEPTION_HISTORY_LEN'

if ($null -in @($lastInterruptVector, $interruptCount, $lastExceptionVector, $exceptionCount, $lastExceptionCode, $interruptHistoryLen, $exceptionHistoryLen)) {
    throw 'Missing aggregate interrupt/exception fields in descriptor-dispatch probe output.'
}
if ($lastInterruptVector -ne 13) { throw "Expected LAST_INTERRUPT_VECTOR=13. got $lastInterruptVector" }
if ($interruptCount -ne 2) { throw "Expected INTERRUPT_COUNT=2. got $interruptCount" }
if ($lastExceptionVector -ne 13) { throw "Expected LAST_EXCEPTION_VECTOR=13. got $lastExceptionVector" }
if ($exceptionCount -ne 1) { throw "Expected EXCEPTION_COUNT=1. got $exceptionCount" }
if ($lastExceptionCode -ne 51966) { throw "Expected LAST_EXCEPTION_CODE=51966. got $lastExceptionCode" }
if ($interruptHistoryLen -ne 2) { throw "Expected INTERRUPT_HISTORY_LEN=2. got $interruptHistoryLen" }
if ($exceptionHistoryLen -ne 1) { throw "Expected EXCEPTION_HISTORY_LEN=1. got $exceptionHistoryLen" }

Write-Output 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_AGGREGATE_STATE_PROBE=pass'
Write-Output "LAST_INTERRUPT_VECTOR=$lastInterruptVector"
Write-Output "INTERRUPT_COUNT=$interruptCount"
Write-Output "LAST_EXCEPTION_VECTOR=$lastExceptionVector"
Write-Output "EXCEPTION_COUNT=$exceptionCount"
Write-Output "LAST_EXCEPTION_CODE=$lastExceptionCode"
Write-Output "INTERRUPT_HISTORY_LEN=$interruptHistoryLen"
Write-Output "EXCEPTION_HISTORY_LEN=$exceptionHistoryLen"
