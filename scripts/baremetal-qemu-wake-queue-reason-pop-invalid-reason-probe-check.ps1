# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-wake-queue-reason-pop-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_INVALID_REASON_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_INVALID_REASON_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-wake-queue-reason-pop-probe-check.ps1' `
    -FailureLabel 'wake-queue reason-pop'
$probeText = $probeState.Text


$lastOpcode = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_LAST_OPCODE'
$lastResult = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_LAST_RESULT'

if ($null -in @($lastOpcode, $lastResult)) {
    throw 'Missing expected invalid-reason fields in wake-queue reason-pop probe output.'
}
if ($lastOpcode -ne 59) { throw "Expected LAST_OPCODE=59. got $lastOpcode" }
if ($lastResult -ne -22) { throw "Expected LAST_RESULT=-22. got $lastResult" }

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_INVALID_REASON_PROBE=pass'
Write-Output "LAST_OPCODE=$lastOpcode"
Write-Output "LAST_RESULT=$lastResult"
