# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-descriptor-bootdiag-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE=skipped\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_BASELINE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_BASELINE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-descriptor-bootdiag-probe-check.ps1' `
    -FailureLabel 'descriptor-bootdiag'
$probeText = $probeState.Text

$ack = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE_ACK'
$lastOpcode = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE_LAST_OPCODE'
$lastResult = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE_LAST_RESULT'
$bootSeqBefore = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE_BOOT_SEQ_BEFORE'
$descriptorReadyBefore = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE_DESCRIPTOR_READY_BEFORE'
$descriptorLoadedBefore = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE_DESCRIPTOR_LOADED_BEFORE'
$loadAttemptsBefore = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE_LOAD_ATTEMPTS_BEFORE'
$loadSuccessesBefore = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE_LOAD_SUCCESSES_BEFORE'
$descriptorInitBefore = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE_DESCRIPTOR_INIT_BEFORE'

if ($null -in @($ack, $lastOpcode, $lastResult, $bootSeqBefore, $descriptorReadyBefore, $descriptorLoadedBefore, $loadAttemptsBefore, $loadSuccessesBefore, $descriptorInitBefore)) {
    throw 'Missing expected baseline fields in descriptor-bootdiag probe output.'
}
if ($ack -ne 6) { throw "Expected ACK=6. got $ack" }
if ($lastOpcode -ne 10) { throw "Expected LAST_OPCODE=10. got $lastOpcode" }
if ($lastResult -ne 0) { throw "Expected LAST_RESULT=0. got $lastResult" }
if ($bootSeqBefore -ne 0) { throw "Expected BOOT_SEQ_BEFORE=0. got $bootSeqBefore" }
if ($descriptorReadyBefore -ne 1) { throw "Expected DESCRIPTOR_READY_BEFORE=1. got $descriptorReadyBefore" }
if ($descriptorLoadedBefore -ne 1) { throw "Expected DESCRIPTOR_LOADED_BEFORE=1. got $descriptorLoadedBefore" }
if ($loadAttemptsBefore -lt 1) { throw "Expected LOAD_ATTEMPTS_BEFORE>=1. got $loadAttemptsBefore" }
if ($loadSuccessesBefore -lt 1) { throw "Expected LOAD_SUCCESSES_BEFORE>=1. got $loadSuccessesBefore" }
if ($descriptorInitBefore -lt 1) { throw "Expected DESCRIPTOR_INIT_BEFORE>=1. got $descriptorInitBefore" }

Write-Output 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_BASELINE_PROBE=pass'
Write-Output "ACK=$ack"
Write-Output "LAST_OPCODE=$lastOpcode"
Write-Output "LAST_RESULT=$lastResult"
Write-Output "BOOT_SEQ_BEFORE=$bootSeqBefore"
Write-Output "DESCRIPTOR_READY_BEFORE=$descriptorReadyBefore"
Write-Output "DESCRIPTOR_LOADED_BEFORE=$descriptorLoadedBefore"
Write-Output "LOAD_ATTEMPTS_BEFORE=$loadAttemptsBefore"
Write-Output "LOAD_SUCCESSES_BEFORE=$loadSuccessesBefore"
Write-Output "DESCRIPTOR_INIT_BEFORE=$descriptorInitBefore"
