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
    -SkippedReceipt 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_INVALID_PHASE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_INVALID_PHASE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-descriptor-bootdiag-probe-check.ps1' `
    -FailureLabel 'descriptor-bootdiag'
$probeText = $probeState.Text

$invalidResult = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE_INVALID_RESULT'
$phaseAfterInvalid = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE_PHASE_AFTER_INVALID'
$phaseChangesAfterInvalid = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE_PHASE_CHANGES_AFTER_INVALID'

if ($null -in @($invalidResult, $phaseAfterInvalid, $phaseChangesAfterInvalid)) {
    throw 'Missing expected invalid-phase fields in descriptor-bootdiag probe output.'
}
if ($invalidResult -ne -22) { throw "Expected INVALID_RESULT=-22. got $invalidResult" }
if ($phaseAfterInvalid -ne 1) { throw "Expected PHASE_AFTER_INVALID=1. got $phaseAfterInvalid" }
if ($phaseChangesAfterInvalid -ne 1) { throw "Expected PHASE_CHANGES_AFTER_INVALID=1. got $phaseChangesAfterInvalid" }

Write-Output 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_INVALID_PHASE_PROBE=pass'
Write-Output "INVALID_RESULT=$invalidResult"
Write-Output "PHASE_AFTER_INVALID=$phaseAfterInvalid"
Write-Output "PHASE_CHANGES_AFTER_INVALID=$phaseChangesAfterInvalid"
