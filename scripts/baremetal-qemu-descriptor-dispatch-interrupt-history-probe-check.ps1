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
    -SkippedReceipt 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_INTERRUPT_HISTORY_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_INTERRUPT_HISTORY_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-descriptor-dispatch-probe-check.ps1' `
    -FailureLabel 'descriptor-dispatch'
$probeText = $probeState.Text


$seq1 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_INTERRUPT_EVENT1_SEQ'
$vector1 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_INTERRUPT_EVENT1_VECTOR'
$isException1 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_INTERRUPT_EVENT1_IS_EXCEPTION'
$code1 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_INTERRUPT_EVENT1_CODE'
$interruptCount1 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_INTERRUPT_EVENT1_INTERRUPT_COUNT'
$exceptionCount1 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_INTERRUPT_EVENT1_EXCEPTION_COUNT'
$seq2 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_INTERRUPT_EVENT2_SEQ'
$vector2 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_INTERRUPT_EVENT2_VECTOR'
$isException2 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_INTERRUPT_EVENT2_IS_EXCEPTION'
$code2 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_INTERRUPT_EVENT2_CODE'
$interruptCount2 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_INTERRUPT_EVENT2_INTERRUPT_COUNT'
$exceptionCount2 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_INTERRUPT_EVENT2_EXCEPTION_COUNT'

if ($null -in @($seq1, $vector1, $isException1, $code1, $interruptCount1, $exceptionCount1, $seq2, $vector2, $isException2, $code2, $interruptCount2, $exceptionCount2)) {
    throw 'Missing interrupt-history payload fields in descriptor-dispatch probe output.'
}
if ($seq1 -ne 1 -or $vector1 -ne 44 -or $isException1 -ne 0 -or $code1 -ne 0 -or $interruptCount1 -ne 1 -or $exceptionCount1 -ne 0) {
    throw "Unexpected interrupt event 1 payload: seq=$seq1 vector=$vector1 is_exception=$isException1 code=$code1 interrupt_count=$interruptCount1 exception_count=$exceptionCount1"
}
if ($seq2 -ne 2 -or $vector2 -ne 13 -or $isException2 -ne 1 -or $code2 -ne 51966 -or $interruptCount2 -ne 2 -or $exceptionCount2 -ne 1) {
    throw "Unexpected interrupt event 2 payload: seq=$seq2 vector=$vector2 is_exception=$isException2 code=$code2 interrupt_count=$interruptCount2 exception_count=$exceptionCount2"
}

Write-Output 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_INTERRUPT_HISTORY_PROBE=pass'
Write-Output "INTERRUPT_EVENT1_SEQ=$seq1"
Write-Output "INTERRUPT_EVENT1_VECTOR=$vector1"
Write-Output "INTERRUPT_EVENT1_IS_EXCEPTION=$isException1"
Write-Output "INTERRUPT_EVENT1_CODE=$code1"
Write-Output "INTERRUPT_EVENT1_INTERRUPT_COUNT=$interruptCount1"
Write-Output "INTERRUPT_EVENT1_EXCEPTION_COUNT=$exceptionCount1"
Write-Output "INTERRUPT_EVENT2_SEQ=$seq2"
Write-Output "INTERRUPT_EVENT2_VECTOR=$vector2"
Write-Output "INTERRUPT_EVENT2_IS_EXCEPTION=$isException2"
Write-Output "INTERRUPT_EVENT2_CODE=$code2"
Write-Output "INTERRUPT_EVENT2_INTERRUPT_COUNT=$interruptCount2"
Write-Output "INTERRUPT_EVENT2_EXCEPTION_COUNT=$exceptionCount2"
