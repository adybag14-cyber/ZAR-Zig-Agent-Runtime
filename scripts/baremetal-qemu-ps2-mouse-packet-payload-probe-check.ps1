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
    -SkippedReceipt 'BAREMETAL_QEMU_PS2_MOUSE_PACKET_PAYLOAD_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_PS2_MOUSE_PACKET_PAYLOAD_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-ps2-input-probe-check.ps1' `
    -FailureLabel 'PS/2' `
    -EchoOnSuccess:$true `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true `
    -EmitSkippedSourceReceipt:$true
$probeText = $probeState.Text

$seq = Extract-IntValue -Text $probeText -Name 'MOUSE_PACKET0_SEQ'
$buttons = Extract-IntValue -Text $probeText -Name 'MOUSE_PACKET0_BUTTONS'
$dx = Extract-IntValue -Text $probeText -Name 'MOUSE_PACKET0_DX'
$dy = Extract-IntValue -Text $probeText -Name 'MOUSE_PACKET0_DY'
$tick = Extract-IntValue -Text $probeText -Name 'MOUSE_PACKET0_TICK'
$interruptSeq = Extract-IntValue -Text $probeText -Name 'MOUSE_PACKET0_INTERRUPT_SEQ'
if ($null -in @($seq, $buttons, $dx, $dy, $tick, $interruptSeq)) {
    throw 'Missing mouse packet payload fields in PS/2 probe output.'
}
if ($seq -ne 1) { throw "Expected MOUSE_PACKET0_SEQ=1, got $seq" }
if ($buttons -ne 5) { throw "Expected MOUSE_PACKET0_BUTTONS=5, got $buttons" }
if ($dx -ne 6) { throw "Expected MOUSE_PACKET0_DX=6, got $dx" }
if ($dy -ne -3) { throw "Expected MOUSE_PACKET0_DY=-3, got $dy" }
if ($tick -ne 3) { throw "Expected MOUSE_PACKET0_TICK=3, got $tick" }
if ($interruptSeq -ne 3) { throw "Expected MOUSE_PACKET0_INTERRUPT_SEQ=3, got $interruptSeq" }

Write-Output 'BAREMETAL_QEMU_PS2_MOUSE_PACKET_PAYLOAD_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_PS2_MOUSE_PACKET_PAYLOAD_PROBE_SOURCE=baremetal-qemu-ps2-input-probe-check.ps1'
Write-Output "MOUSE_PACKET0_SEQ=$seq"
Write-Output "MOUSE_PACKET0_BUTTONS=$buttons"
Write-Output "MOUSE_PACKET0_DX=$dx"
Write-Output "MOUSE_PACKET0_DY=$dy"
Write-Output "MOUSE_PACKET0_TICK=$tick"
Write-Output "MOUSE_PACKET0_INTERRUPT_SEQ=$interruptSeq"
