# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-interrupt-manual-wake-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe -ProbePath $probe -SkipBuild:$SkipBuild -SkippedPattern '(?m)^BAREMETAL_QEMU_INTERRUPT_MANUAL_WAKE_PROBE=skipped\r?$' -SkippedReceipt 'BAREMETAL_QEMU_INTERRUPT_MANUAL_WAKE_TELEMETRY_PRESERVE_PROBE' -SkippedSourceReceipt 'BAREMETAL_QEMU_INTERRUPT_MANUAL_WAKE_TELEMETRY_PRESERVE_PROBE_SOURCE' -SkippedSourceValue 'baremetal-qemu-interrupt-manual-wake-probe-check.ps1' -FailureLabel 'interrupt-manual-wake' -EchoOnSuccess:$false -EchoOnSkip:$true -EchoOnFailure:$true -TrimEchoText:$true -EmitSkippedSourceReceipt:$true
$probeText = $probeState.Text
$ack = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MANUAL_WAKE_PROBE_ACK'
$mailboxOpcode = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MANUAL_WAKE_PROBE_MAILBOX_OPCODE'
$mailboxSeq = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MANUAL_WAKE_PROBE_MAILBOX_SEQ'
$timerEnabled = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MANUAL_WAKE_PROBE_TIMER_ENABLED'
$timerPendingWakeCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MANUAL_WAKE_PROBE_TIMER_PENDING_WAKE_COUNT'
$timerDispatchCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MANUAL_WAKE_PROBE_TIMER_DISPATCH_COUNT'
$timerLastInterruptCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MANUAL_WAKE_PROBE_TIMER_LAST_INTERRUPT_COUNT'
$timerLastWakeTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MANUAL_WAKE_PROBE_TIMER_LAST_WAKE_TICK'
$wake0Tick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MANUAL_WAKE_PROBE_WAKE0_TICK'
$ticks = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MANUAL_WAKE_PROBE_TICKS'
if ($null -in @($ack,$mailboxOpcode,$mailboxSeq,$timerEnabled,$timerPendingWakeCount,$timerDispatchCount,$timerLastInterruptCount,$timerLastWakeTick,$wake0Tick,$ticks)) {
    throw 'Missing expected interrupt-manual-wake telemetry fields in probe output.'
}
if ($ack -ne 8) { throw "Expected ACK=8. got $ack" }
if ($mailboxOpcode -ne 7) { throw "Expected MAILBOX_OPCODE=7. got $mailboxOpcode" }
if ($mailboxSeq -ne 8) { throw "Expected MAILBOX_SEQ=8. got $mailboxSeq" }
if ($timerEnabled -ne 1) { throw "Expected TIMER_ENABLED=1. got $timerEnabled" }
if ($timerPendingWakeCount -ne 1) { throw "Expected TIMER_PENDING_WAKE_COUNT=1. got $timerPendingWakeCount" }
if ($timerDispatchCount -ne 0) { throw "Expected TIMER_DISPATCH_COUNT=0. got $timerDispatchCount" }
if ($timerLastInterruptCount -ne 1) { throw "Expected TIMER_LAST_INTERRUPT_COUNT=1. got $timerLastInterruptCount" }
if ($timerLastWakeTick -ne $wake0Tick) { throw "Expected TIMER_LAST_WAKE_TICK=$wake0Tick. got $timerLastWakeTick" }
if ($ticks -lt ($wake0Tick + 8)) { throw "Expected TICKS >= WAKE0_TICK+8. got TICKS=$ticks WAKE0_TICK=$wake0Tick" }
Write-Output 'BAREMETAL_QEMU_INTERRUPT_MANUAL_WAKE_TELEMETRY_PRESERVE_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_INTERRUPT_MANUAL_WAKE_TELEMETRY_PRESERVE_PROBE_SOURCE=baremetal-qemu-interrupt-manual-wake-probe-check.ps1'
Write-Output "ACK=$ack"
Write-Output "MAILBOX_OPCODE=$mailboxOpcode"
Write-Output "MAILBOX_SEQ=$mailboxSeq"
Write-Output "TIMER_ENABLED=$timerEnabled"
Write-Output "TIMER_PENDING_WAKE_COUNT=$timerPendingWakeCount"
Write-Output "TIMER_DISPATCH_COUNT=$timerDispatchCount"
Write-Output "TIMER_LAST_INTERRUPT_COUNT=$timerLastInterruptCount"
Write-Output "TIMER_LAST_WAKE_TICK=$timerLastWakeTick"
Write-Output "WAKE0_TICK=$wake0Tick"
Write-Output "TICKS=$ticks"
