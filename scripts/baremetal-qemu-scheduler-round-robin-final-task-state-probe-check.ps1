# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-scheduler-round-robin-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_SCHEDULER_ROUND_ROBIN_PROBE=skipped\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_SCHEDULER_ROUND_ROBIN_FINAL_TASK_STATE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_SCHEDULER_ROUND_ROBIN_FINAL_TASK_STATE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-scheduler-round-robin-probe-check.ps1' `
    -FailureLabel 'scheduler-round-robin'
$probeText = $probeState.Text

$ack = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_ROUND_ROBIN_ACK'
$lastOpcode = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_ROUND_ROBIN_LAST_OPCODE'
$lastResult = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_ROUND_ROBIN_LAST_RESULT'
$ticks = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_ROUND_ROBIN_TICKS'
$taskCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_ROUND_ROBIN_TASK_COUNT'
$dispatchCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_ROUND_ROBIN_DISPATCH_COUNT'
$policy = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_ROUND_ROBIN_POLICY'

if ($null -in @($ack, $lastOpcode, $lastResult, $ticks, $taskCount, $dispatchCount, $policy)) {
    throw 'Missing expected final-state fields in scheduler-round-robin probe output.'
}
if ($ack -ne 6) { throw "Expected ACK=6. got $ack" }
if ($lastOpcode -ne 24) { throw "Expected LAST_OPCODE=24. got $lastOpcode" }
if ($lastResult -ne 0) { throw "Expected LAST_RESULT=0. got $lastResult" }
if ($ticks -lt 8) { throw "Expected TICKS >= 8. got $ticks" }
if ($taskCount -ne 2) { throw "Expected TASK_COUNT=2. got $taskCount" }
if ($dispatchCount -lt 3) { throw "Expected DISPATCH_COUNT >= 3. got $dispatchCount" }
if ($policy -ne 0) { throw "Expected POLICY=0. got $policy" }

Write-Output 'BAREMETAL_QEMU_SCHEDULER_ROUND_ROBIN_FINAL_TASK_STATE_PROBE=pass'
Write-Output "ACK=$ack"
Write-Output "LAST_OPCODE=$lastOpcode"
Write-Output "LAST_RESULT=$lastResult"
Write-Output "TICKS=$ticks"
Write-Output "TASK_COUNT=$taskCount"
Write-Output "DISPATCH_COUNT=$dispatchCount"
Write-Output "POLICY=$policy"
