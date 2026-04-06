# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-allocator-saturation-reset-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_ALLOCATOR_SATURATION_RESET_PROBE=skipped\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_ALLOCATOR_SATURATION_RESET_BASELINE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_ALLOCATOR_SATURATION_RESET_BASELINE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-allocator-saturation-reset-probe-check.ps1' `
    -FailureLabel 'allocator saturation-reset'
$probeText = $probeState.Text
$lastOpcode = Extract-IntValue -Text $probeText -Name 'LAST_OPCODE'
$lastResult = Extract-IntValue -Text $probeText -Name 'LAST_RESULT'
$statusMode = Extract-IntValue -Text $probeText -Name 'STATUS_MODE'
$preResetAllocationCount = Extract-IntValue -Text $probeText -Name 'PRE_RESET_ALLOCATION_COUNT'
$preResetFreePages = Extract-IntValue -Text $probeText -Name 'PRE_RESET_FREE_PAGES'
if ($null -in @($ack,$lastOpcode,$lastResult,$statusMode,$preResetAllocationCount,$preResetFreePages)) { throw 'Missing baseline allocator saturation-reset fields.' }
if ($ack -ne 68) { throw "Expected ACK=68. got $ack" }
if ($lastOpcode -ne 32) { throw "Expected LAST_OPCODE=32. got $lastOpcode" }
if ($lastResult -ne 0) { throw "Expected LAST_RESULT=0. got $lastResult" }
if ($statusMode -ne 1) { throw "Expected STATUS_MODE=1. got $statusMode" }
if ($preResetAllocationCount -ne 64) { throw "Expected PRE_RESET_ALLOCATION_COUNT=64. got $preResetAllocationCount" }
if ($preResetFreePages -ne 192) { throw "Expected PRE_RESET_FREE_PAGES=192. got $preResetFreePages" }
Write-Output 'BAREMETAL_QEMU_ALLOCATOR_SATURATION_RESET_BASELINE_PROBE=pass'
Write-Output "ACK=$ack"
Write-Output "LAST_OPCODE=$lastOpcode"
Write-Output "LAST_RESULT=$lastResult"
Write-Output "STATUS_MODE=$statusMode"
Write-Output "PRE_RESET_ALLOCATION_COUNT=$preResetAllocationCount"
Write-Output "PRE_RESET_FREE_PAGES=$preResetFreePages"
