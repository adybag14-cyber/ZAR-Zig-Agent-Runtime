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
    -SkippedReceipt 'BAREMETAL_QEMU_PS2_INPUT_BASELINE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_PS2_INPUT_BASELINE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-ps2-input-probe-check.ps1' `
    -FailureLabel 'PS/2' `
    -EchoOnSuccess:$true `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true `
    -EmitSkippedSourceReceipt:$true
$probeText = $probeState.Text

$mailboxAck = Extract-IntValue -Text $probeText -Name 'MAILBOX_ACK'
$mailboxLastOpcode = Extract-IntValue -Text $probeText -Name 'MAILBOX_LAST_OPCODE'
$mailboxLastResult = Extract-IntValue -Text $probeText -Name 'MAILBOX_LAST_RESULT'
$keyboardConnected = Extract-IntValue -Text $probeText -Name 'KEYBOARD_CONNECTED'
$mouseConnected = Extract-IntValue -Text $probeText -Name 'MOUSE_CONNECTED'
if ($null -in @($mailboxAck, $mailboxLastOpcode, $mailboxLastResult, $keyboardConnected, $mouseConnected)) {
    throw 'Missing baseline fields in PS/2 probe output.'
}
if ($mailboxAck -ne 3) { throw "Expected MAILBOX_ACK=3, got $mailboxAck" }
if ($mailboxLastOpcode -ne 7) { throw "Expected MAILBOX_LAST_OPCODE=7, got $mailboxLastOpcode" }
if ($mailboxLastResult -ne 0) { throw "Expected MAILBOX_LAST_RESULT=0, got $mailboxLastResult" }
if ($keyboardConnected -ne 1) { throw "Expected KEYBOARD_CONNECTED=1, got $keyboardConnected" }
if ($mouseConnected -ne 1) { throw "Expected MOUSE_CONNECTED=1, got $mouseConnected" }

Write-Output 'BAREMETAL_QEMU_PS2_INPUT_BASELINE_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_PS2_INPUT_BASELINE_PROBE_SOURCE=baremetal-qemu-ps2-input-probe-check.ps1'
Write-Output "MAILBOX_ACK=$mailboxAck"
Write-Output "MAILBOX_LAST_OPCODE=$mailboxLastOpcode"
Write-Output "MAILBOX_LAST_RESULT=$mailboxLastResult"
Write-Output "KEYBOARD_CONNECTED=$keyboardConnected"
Write-Output "MOUSE_CONNECTED=$mouseConnected"
