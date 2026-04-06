# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-allocator-syscall-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_ALLOCATOR_SYSCALL_PROBE=skipped\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_INVOKE_STAGE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_INVOKE_STAGE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-allocator-syscall-probe-check.ps1' `
    -FailureLabel 'allocator-syscall'
$probeText = $probeState.Text

$invokeResult = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_PROBE_INVOKE_LAST_RESULT_SNAPSHOT'
$dispatchCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_PROBE_INVOKE_DISPATCH_COUNT_SNAPSHOT'
$invokeCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_PROBE_INVOKE_COUNT_SNAPSHOT'
$lastArg = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_PROBE_INVOKE_LAST_ARG_SNAPSHOT'
if ($null -in @($invokeResult,$dispatchCount,$invokeCount,$lastArg)) { throw 'Missing invoke stage fields.' }
if ($invokeResult -ne 47206) { throw "Expected INVOKE_LAST_RESULT_SNAPSHOT=47206. got $invokeResult" }
if ($dispatchCount -ne 1) { throw "Expected INVOKE_DISPATCH_COUNT_SNAPSHOT=1. got $dispatchCount" }
if ($invokeCount -ne 1) { throw "Expected INVOKE_COUNT_SNAPSHOT=1. got $invokeCount" }
if ($lastArg -ne 4660) { throw "Expected INVOKE_LAST_ARG_SNAPSHOT=4660. got $lastArg" }
Write-Output 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_INVOKE_STAGE_PROBE=pass'
Write-Output "INVOKE_LAST_RESULT_SNAPSHOT=$invokeResult"
Write-Output "INVOKE_DISPATCH_COUNT_SNAPSHOT=$dispatchCount"
Write-Output "INVOKE_COUNT_SNAPSHOT=$invokeCount"
Write-Output "INVOKE_LAST_ARG_SNAPSHOT=$lastArg"
