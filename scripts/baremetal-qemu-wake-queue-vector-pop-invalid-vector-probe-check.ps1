# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-wake-queue-vector-pop-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_WAKE_QUEUE_VECTOR_POP_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_VECTOR_POP_INVALID_VECTOR_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_VECTOR_POP_INVALID_VECTOR_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-wake-queue-vector-pop-probe-check.ps1' `
    -FailureLabel 'wake-queue vector-pop'
$probeText = $probeState.Text

$lastOpcode = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_VECTOR_POP_LAST_OPCODE'
$lastResult = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_VECTOR_POP_LAST_RESULT'
if ($null -in @($lastOpcode,$lastResult)) { throw 'Missing expected invalid-vector fields in wake-queue vector-pop probe output.' }
if ($lastOpcode -ne 60) { throw "Expected LAST_OPCODE=60. got $lastOpcode" }
if ($lastResult -ne -2) { throw "Expected LAST_RESULT=-2. got $lastResult" }
Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_VECTOR_POP_INVALID_VECTOR_PROBE=pass'
Write-Output "LAST_OPCODE=$lastOpcode"
Write-Output "LAST_RESULT=$lastResult"
