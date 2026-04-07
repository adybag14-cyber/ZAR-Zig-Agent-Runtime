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
    -SkippedReceipt 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_SET_INIT_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_SET_INIT_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-descriptor-bootdiag-probe-check.ps1' `
    -FailureLabel 'descriptor-bootdiag'
$probeText = $probeState.Text

$phaseAfterSetInit = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE_PHASE_AFTER_SET_INIT'
$lastCommandSeqAfterSetInit = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE_LAST_COMMAND_SEQ_AFTER_SET_INIT'
$phaseChangesAfterSetInit = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE_PHASE_CHANGES_AFTER_SET_INIT'

if ($null -in @($phaseAfterSetInit, $lastCommandSeqAfterSetInit, $phaseChangesAfterSetInit)) {
    throw 'Missing expected set-init fields in descriptor-bootdiag probe output.'
}
if ($phaseAfterSetInit -ne 1) { throw "Expected PHASE_AFTER_SET_INIT=1. got $phaseAfterSetInit" }
if ($lastCommandSeqAfterSetInit -ne 3) { throw "Expected LAST_COMMAND_SEQ_AFTER_SET_INIT=3. got $lastCommandSeqAfterSetInit" }
if ($phaseChangesAfterSetInit -ne 1) { throw "Expected PHASE_CHANGES_AFTER_SET_INIT=1. got $phaseChangesAfterSetInit" }

Write-Output 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_SET_INIT_PROBE=pass'
Write-Output "PHASE_AFTER_SET_INIT=$phaseAfterSetInit"
Write-Output "LAST_COMMAND_SEQ_AFTER_SET_INIT=$lastCommandSeqAfterSetInit"
Write-Output "PHASE_CHANGES_AFTER_SET_INIT=$phaseChangesAfterSetInit"
