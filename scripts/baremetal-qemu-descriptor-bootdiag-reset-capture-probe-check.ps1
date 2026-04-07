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
    -SkippedReceipt 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_RESET_CAPTURE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_RESET_CAPTURE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-descriptor-bootdiag-probe-check.ps1' `
    -FailureLabel 'descriptor-bootdiag'
$probeText = $probeState.Text

$bootSeqBefore = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE_BOOT_SEQ_BEFORE'
$bootSeqAfterReset = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE_BOOT_SEQ_AFTER_RESET'
$phaseAfterReset = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE_PHASE_AFTER_RESET'
$lastCommandSeqAfterReset = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE_LAST_COMMAND_SEQ_AFTER_RESET'
$phaseChangesAfterReset = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE_PHASE_CHANGES_AFTER_RESET'
$stackSnapshotAfterCapture = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE_STACK_SNAPSHOT_AFTER_CAPTURE'
$lastCommandSeqAfterCapture = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE_LAST_COMMAND_SEQ_AFTER_CAPTURE'

if ($null -in @($bootSeqBefore, $bootSeqAfterReset, $phaseAfterReset, $lastCommandSeqAfterReset, $phaseChangesAfterReset, $stackSnapshotAfterCapture, $lastCommandSeqAfterCapture)) {
    throw 'Missing expected reset/capture fields in descriptor-bootdiag probe output.'
}
if ($bootSeqAfterReset -ne ($bootSeqBefore + 1)) { throw "Expected BOOT_SEQ_AFTER_RESET=BOOT_SEQ_BEFORE+1. got $bootSeqAfterReset vs $bootSeqBefore" }
if ($phaseAfterReset -ne 2) { throw "Expected PHASE_AFTER_RESET=2. got $phaseAfterReset" }
if ($lastCommandSeqAfterReset -ne 1) { throw "Expected LAST_COMMAND_SEQ_AFTER_RESET=1. got $lastCommandSeqAfterReset" }
if ($phaseChangesAfterReset -ne 0) { throw "Expected PHASE_CHANGES_AFTER_RESET=0. got $phaseChangesAfterReset" }
if ($stackSnapshotAfterCapture -le 0) { throw "Expected STACK_SNAPSHOT_AFTER_CAPTURE>0. got $stackSnapshotAfterCapture" }
if ($lastCommandSeqAfterCapture -ne 2) { throw "Expected LAST_COMMAND_SEQ_AFTER_CAPTURE=2. got $lastCommandSeqAfterCapture" }

Write-Output 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_RESET_CAPTURE_PROBE=pass'
Write-Output "BOOT_SEQ_BEFORE=$bootSeqBefore"
Write-Output "BOOT_SEQ_AFTER_RESET=$bootSeqAfterReset"
Write-Output "PHASE_AFTER_RESET=$phaseAfterReset"
Write-Output "LAST_COMMAND_SEQ_AFTER_RESET=$lastCommandSeqAfterReset"
Write-Output "PHASE_CHANGES_AFTER_RESET=$phaseChangesAfterReset"
Write-Output "STACK_SNAPSHOT_AFTER_CAPTURE=$stackSnapshotAfterCapture"
Write-Output "LAST_COMMAND_SEQ_AFTER_CAPTURE=$lastCommandSeqAfterCapture"
