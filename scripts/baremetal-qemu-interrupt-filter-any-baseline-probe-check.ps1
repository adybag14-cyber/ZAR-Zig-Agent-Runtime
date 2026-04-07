# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-interrupt-filter-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe 
    -SkipBuild:$SkipBuild 
    -SkippedPattern '(?m)^BAREMETAL_QEMU_INTERRUPT_FILTER_PROBE=skipped\r?$' 
    -SkippedReceipt 'BAREMETAL_QEMU_INTERRUPT_FILTER_ANY_BASELINE_PROBE' 
    -SkippedSourceReceipt 'BAREMETAL_QEMU_INTERRUPT_FILTER_ANY_BASELINE_PROBE_SOURCE' 
    -SkippedSourceValue 'baremetal-qemu-interrupt-filter-probe-check.ps1' 
    -FailureLabel 'interrupt-filter' 
    -EmitSkippedSourceReceipt:$true
$probeText = $probeState.Text
task0Id = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_FILTER_TASK0_ID'
$anyWaitCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_FILTER_ANY_WAIT_COUNT_BEFORE_WAKE'
$anyWaitKind = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_FILTER_ANY_WAIT_KIND_BEFORE_WAKE'
$anyWaitVector = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_FILTER_ANY_WAIT_VECTOR_BEFORE_WAKE'
$anyWaitTaskCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_FILTER_ANY_WAIT_TASK_COUNT_BEFORE_WAKE'
$anyWaitTaskState = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_FILTER_ANY_WAIT_TASK_STATE_BEFORE_WAKE'
if ($null -in @($task0Id, $anyWaitCount, $anyWaitKind, $anyWaitVector, $anyWaitTaskCount, $anyWaitTaskState)) { throw 'Missing any-baseline fields in interrupt-filter probe output.' }
if ($task0Id -le 0) { throw "Expected TASK0_ID > 0, got $task0Id" }
if ($anyWaitCount -ne 1) { throw "Expected ANY_WAIT_COUNT_BEFORE_WAKE=1, got $anyWaitCount" }
if ($anyWaitKind -ne 3) { throw "Expected ANY_WAIT_KIND_BEFORE_WAKE=3, got $anyWaitKind" }
if ($anyWaitVector -ne 0) { throw "Expected ANY_WAIT_VECTOR_BEFORE_WAKE=0, got $anyWaitVector" }
if ($anyWaitTaskCount -ne 0) { throw "Expected ANY_WAIT_TASK_COUNT_BEFORE_WAKE=0, got $anyWaitTaskCount" }
if ($anyWaitTaskState -ne 6) { throw "Expected ANY_WAIT_TASK_STATE_BEFORE_WAKE=6, got $anyWaitTaskState" }
Write-Output 'BAREMETAL_QEMU_INTERRUPT_FILTER_ANY_BASELINE_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_INTERRUPT_FILTER_ANY_BASELINE_PROBE_SOURCE=baremetal-qemu-interrupt-filter-probe-check.ps1'
Write-Output "TASK0_ID=$task0Id"
Write-Output "ANY_WAIT_COUNT_BEFORE_WAKE=$anyWaitCount"
Write-Output "ANY_WAIT_KIND_BEFORE_WAKE=$anyWaitKind"
Write-Output "ANY_WAIT_VECTOR_BEFORE_WAKE=$anyWaitVector"
Write-Output "ANY_WAIT_TASK_COUNT_BEFORE_WAKE=$anyWaitTaskCount"
Write-Output "ANY_WAIT_TASK_STATE_BEFORE_WAKE=$anyWaitTaskState"
