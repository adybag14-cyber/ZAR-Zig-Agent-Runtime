# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-task-terminate-interrupt-timeout-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_TASK_TERMINATE_INTERRUPT_TIMEOUT_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_TASK_TERMINATE_INTERRUPT_TIMEOUT_MAILBOX_STATE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_TASK_TERMINATE_INTERRUPT_TIMEOUT_MAILBOX_STATE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-task-terminate-interrupt-timeout-probe-check.ps1' `
    -FailureLabel 'task-terminate interrupt-timeout' `
    -EchoOnSuccess:$false `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true `
    -TrimEchoText:$true `
    -EmitSkippedSourceReceipt:$true
$probeText = $probeState.Text

$ack = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TASK_TERMINATE_INTERRUPT_TIMEOUT_PROBE_ACK'
$lastOpcode = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TASK_TERMINATE_INTERRUPT_TIMEOUT_PROBE_LAST_OPCODE'
$lastResult = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TASK_TERMINATE_INTERRUPT_TIMEOUT_PROBE_LAST_RESULT'
$mailboxOpcode = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TASK_TERMINATE_INTERRUPT_TIMEOUT_PROBE_MAILBOX_OPCODE'
$mailboxSeq = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TASK_TERMINATE_INTERRUPT_TIMEOUT_PROBE_MAILBOX_SEQ'
$task0Budget = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TASK_TERMINATE_INTERRUPT_TIMEOUT_PROBE_TASK0_BUDGET'
$task0BudgetRemaining = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TASK_TERMINATE_INTERRUPT_TIMEOUT_PROBE_TASK0_BUDGET_REMAINING'

if ($null -in @($ack, $lastOpcode, $lastResult, $mailboxOpcode, $mailboxSeq, $task0Budget, $task0BudgetRemaining)) {
    throw 'Missing expected mailbox/final-state fields in task-terminate interrupt-timeout probe output.'
}
if ($ack -ne 8) { throw "Expected ACK=8. got $ack" }
if ($lastOpcode -ne 7) { throw "Expected LAST_OPCODE=7. got $lastOpcode" }
if ($lastResult -ne 0) { throw "Expected LAST_RESULT=0. got $lastResult" }
if ($mailboxOpcode -ne 7) { throw "Expected MAILBOX_OPCODE=7. got $mailboxOpcode" }
if ($mailboxSeq -ne 8) { throw "Expected MAILBOX_SEQ=8. got $mailboxSeq" }
if ($task0Budget -ne 5) { throw "Expected TASK0_BUDGET=5. got $task0Budget" }
if ($task0BudgetRemaining -ne 0) { throw "Expected TASK0_BUDGET_REMAINING=0. got $task0BudgetRemaining" }

Write-Output 'BAREMETAL_QEMU_TASK_TERMINATE_INTERRUPT_TIMEOUT_MAILBOX_STATE_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_TASK_TERMINATE_INTERRUPT_TIMEOUT_MAILBOX_STATE_PROBE_SOURCE=baremetal-qemu-task-terminate-interrupt-timeout-probe-check.ps1'
Write-Output "ACK=$ack"
Write-Output "LAST_OPCODE=$lastOpcode"
Write-Output "LAST_RESULT=$lastResult"
Write-Output "MAILBOX_OPCODE=$mailboxOpcode"
Write-Output "MAILBOX_SEQ=$mailboxSeq"
Write-Output "TASK0_BUDGET=$task0Budget"
Write-Output "TASK0_BUDGET_REMAINING=$task0BudgetRemaining"
