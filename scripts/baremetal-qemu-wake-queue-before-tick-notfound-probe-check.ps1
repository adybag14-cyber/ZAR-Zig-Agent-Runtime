# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-wake-queue-before-tick-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_NOTFOUND_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_NOTFOUND_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-wake-queue-before-tick-probe-check.ps1' `
    -FailureLabel 'wake-queue before-tick'
$probeText = $probeState.Text


$ack = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_ACK'
$lastOpcode = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_LAST_OPCODE'
$lastResult = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_LAST_RESULT'
if ($null -in @($ack,$lastOpcode,$lastResult)) {
    throw 'Missing expected notfound fields in wake-queue before-tick probe output.'
}
if ($ack -ne 19) { throw "Expected ACK=19. got $ack" }
if ($lastOpcode -ne 61) { throw "Expected LAST_OPCODE=61. got $lastOpcode" }
if ($lastResult -ne -2) { throw "Expected LAST_RESULT=-2. got $lastResult" }
Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_NOTFOUND_PROBE=pass'
Write-Output "ACK=$ack"
Write-Output "LAST_OPCODE=$lastOpcode"
Write-Output "LAST_RESULT=$lastResult"

