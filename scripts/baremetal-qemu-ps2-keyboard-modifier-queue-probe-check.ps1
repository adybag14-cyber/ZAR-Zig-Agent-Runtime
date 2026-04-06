# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-ps2-input-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_PS2_INPUT_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_PS2_KEYBOARD_MODIFIER_QUEUE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_PS2_KEYBOARD_MODIFIER_QUEUE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-ps2-input-probe-check.ps1' `
    -FailureLabel 'PS/2' `
    -EchoOnSuccess:$true `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true `
    -EmitSkippedSourceReceipt:$true
$probeText = $probeState.Text

$modifiers = Extract-IntValue -Text $probeText -Name 'KEYBOARD_MODIFIERS'
$queueLen = Extract-IntValue -Text $probeText -Name 'KEYBOARD_QUEUE_LEN'
$eventCount = Extract-IntValue -Text $probeText -Name 'KEYBOARD_EVENT_COUNT'
$lastScancode = Extract-IntValue -Text $probeText -Name 'KEYBOARD_LAST_SCANCODE'
$lastKeycode = Extract-IntValue -Text $probeText -Name 'KEYBOARD_LAST_KEYCODE'
if ($null -in @($modifiers, $queueLen, $eventCount, $lastScancode, $lastKeycode)) {
    throw 'Missing keyboard modifier/queue fields in PS/2 probe output.'
}
if ($modifiers -ne 1) { throw "Expected KEYBOARD_MODIFIERS=1, got $modifiers" }
if ($queueLen -ne 2) { throw "Expected KEYBOARD_QUEUE_LEN=2, got $queueLen" }
if ($eventCount -ne 2) { throw "Expected KEYBOARD_EVENT_COUNT=2, got $eventCount" }
if ($lastScancode -ne 30) { throw "Expected KEYBOARD_LAST_SCANCODE=30, got $lastScancode" }
if ($lastKeycode -ne 65) { throw "Expected KEYBOARD_LAST_KEYCODE=65, got $lastKeycode" }

Write-Output 'BAREMETAL_QEMU_PS2_KEYBOARD_MODIFIER_QUEUE_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_PS2_KEYBOARD_MODIFIER_QUEUE_PROBE_SOURCE=baremetal-qemu-ps2-input-probe-check.ps1'
Write-Output "KEYBOARD_MODIFIERS=$modifiers"
Write-Output "KEYBOARD_QUEUE_LEN=$queueLen"
Write-Output "KEYBOARD_EVENT_COUNT=$eventCount"
Write-Output "KEYBOARD_LAST_SCANCODE=$lastScancode"
Write-Output "KEYBOARD_LAST_KEYCODE=$lastKeycode"
