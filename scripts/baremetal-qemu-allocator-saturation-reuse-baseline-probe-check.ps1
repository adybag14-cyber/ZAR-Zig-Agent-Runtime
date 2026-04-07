# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-allocator-saturation-reuse-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_ALLOCATOR_SATURATION_REUSE_PROBE=skipped\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_ALLOCATOR_SATURATION_REUSE_BASELINE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_ALLOCATOR_SATURATION_REUSE_BASELINE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-allocator-saturation-reuse-probe-check.ps1' `
    -FailureLabel 'allocator saturation-reuse'
$probeText = $probeState.Text
$lastOpcode = Extract-IntValue -Text $probeText -Name 'LAST_OPCODE'
$lastResult = Extract-IntValue -Text $probeText -Name 'LAST_RESULT'
$statusMode = Extract-IntValue -Text $probeText -Name 'STATUS_MODE'
$preFreeAllocationCount = Extract-IntValue -Text $probeText -Name 'PRE_FREE_ALLOCATION_COUNT'
$preFreeFreePages = Extract-IntValue -Text $probeText -Name 'PRE_FREE_FREE_PAGES'
if ($null -in @($ack,$lastOpcode,$lastResult,$statusMode,$preFreeAllocationCount,$preFreeFreePages)) { throw 'Missing baseline allocator saturation-reuse fields.' }
if ($ack -ne 68) { throw "Expected ACK=68. got $ack" }
if ($lastOpcode -ne 32) { throw "Expected LAST_OPCODE=32. got $lastOpcode" }
if ($lastResult -ne 0) { throw "Expected LAST_RESULT=0. got $lastResult" }
if ($statusMode -ne 1) { throw "Expected STATUS_MODE=1. got $statusMode" }
if ($preFreeAllocationCount -ne 64) { throw "Expected PRE_FREE_ALLOCATION_COUNT=64. got $preFreeAllocationCount" }
if ($preFreeFreePages -ne 192) { throw "Expected PRE_FREE_FREE_PAGES=192. got $preFreeFreePages" }
Write-Output 'BAREMETAL_QEMU_ALLOCATOR_SATURATION_REUSE_BASELINE_PROBE=pass'
Write-Output "ACK=$ack"
Write-Output "LAST_OPCODE=$lastOpcode"
Write-Output "LAST_RESULT=$lastResult"
Write-Output "STATUS_MODE=$statusMode"
Write-Output "PRE_FREE_ALLOCATION_COUNT=$preFreeAllocationCount"
Write-Output "PRE_FREE_FREE_PAGES=$preFreeFreePages"
