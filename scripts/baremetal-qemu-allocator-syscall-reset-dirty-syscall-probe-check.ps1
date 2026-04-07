# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-allocator-syscall-reset-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_ALLOCATOR_SYSCALL_RESET_PROBE=skipped\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_RESET_DIRTY_SYSCALL_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_RESET_DIRTY_SYSCALL_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-allocator-syscall-reset-probe-check.ps1' `
    -FailureLabel 'allocator-syscall-reset'
$probeText = $probeState.Text

$dirtySyscallEntryCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_RESET_PROBE_DIRTY_SYSCALL_ENTRY_COUNT'
$dirtySyscallDispatchCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_RESET_PROBE_DIRTY_SYSCALL_DISPATCH_COUNT'
$dirtySyscallLastId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_RESET_PROBE_DIRTY_SYSCALL_LAST_ID'
$dirtySyscallLastInvokeTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_RESET_PROBE_DIRTY_SYSCALL_LAST_INVOKE_TICK'
$dirtySyscallLastResult = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_RESET_PROBE_DIRTY_SYSCALL_LAST_RESULT'
$dirtySyscallEntry0State = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_RESET_PROBE_DIRTY_SYSCALL_ENTRY0_STATE'
$dirtySyscallEntry0Token = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_RESET_PROBE_DIRTY_SYSCALL_ENTRY0_TOKEN'
$dirtySyscallEntry0InvokeCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_RESET_PROBE_DIRTY_SYSCALL_ENTRY0_INVOKE_COUNT'
$dirtySyscallEntry0LastArg = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_RESET_PROBE_DIRTY_SYSCALL_ENTRY0_LAST_ARG'
$dirtySyscallEntry0LastResult = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_RESET_PROBE_DIRTY_SYSCALL_ENTRY0_LAST_RESULT'

if ($null -in @($dirtySyscallEntryCount, $dirtySyscallDispatchCount, $dirtySyscallLastId, $dirtySyscallLastInvokeTick, $dirtySyscallLastResult, $dirtySyscallEntry0State, $dirtySyscallEntry0Token, $dirtySyscallEntry0InvokeCount, $dirtySyscallEntry0LastArg, $dirtySyscallEntry0LastResult)) {
    throw 'Missing expected dirty syscall fields in allocator-syscall-reset probe output.'
}
if ($dirtySyscallEntryCount -ne 1) { throw "Expected DIRTY_SYSCALL_ENTRY_COUNT=1. got $dirtySyscallEntryCount" }
if ($dirtySyscallDispatchCount -ne 1) { throw "Expected DIRTY_SYSCALL_DISPATCH_COUNT=1. got $dirtySyscallDispatchCount" }
if ($dirtySyscallLastId -ne $syscallId) { throw "Expected DIRTY_SYSCALL_LAST_ID=$syscallId. got $dirtySyscallLastId" }
if ($dirtySyscallLastInvokeTick -le 0) { throw "Expected DIRTY_SYSCALL_LAST_INVOKE_TICK > 0. got $dirtySyscallLastInvokeTick" }
if ($dirtySyscallLastResult -ne $expectedInvokeResult) { throw "Expected DIRTY_SYSCALL_LAST_RESULT=$expectedInvokeResult. got $dirtySyscallLastResult" }
if ($dirtySyscallEntry0State -ne 1) { throw "Expected DIRTY_SYSCALL_ENTRY0_STATE=1. got $dirtySyscallEntry0State" }
if ($dirtySyscallEntry0Token -ne $handlerToken) { throw "Expected DIRTY_SYSCALL_ENTRY0_TOKEN=$handlerToken. got $dirtySyscallEntry0Token" }
if ($dirtySyscallEntry0InvokeCount -ne 1) { throw "Expected DIRTY_SYSCALL_ENTRY0_INVOKE_COUNT=1. got $dirtySyscallEntry0InvokeCount" }
if ($dirtySyscallEntry0LastArg -ne $invokeArg) { throw "Expected DIRTY_SYSCALL_ENTRY0_LAST_ARG=$invokeArg. got $dirtySyscallEntry0LastArg" }
if ($dirtySyscallEntry0LastResult -ne $expectedInvokeResult) { throw "Expected DIRTY_SYSCALL_ENTRY0_LAST_RESULT=$expectedInvokeResult. got $dirtySyscallEntry0LastResult" }

Write-Output 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_RESET_DIRTY_SYSCALL_PROBE=pass'
Write-Output "DIRTY_SYSCALL_ENTRY_COUNT=$dirtySyscallEntryCount"
Write-Output "DIRTY_SYSCALL_DISPATCH_COUNT=$dirtySyscallDispatchCount"
Write-Output "DIRTY_SYSCALL_LAST_ID=$dirtySyscallLastId"
Write-Output "DIRTY_SYSCALL_LAST_INVOKE_TICK=$dirtySyscallLastInvokeTick"
Write-Output "DIRTY_SYSCALL_LAST_RESULT=$dirtySyscallLastResult"
Write-Output "DIRTY_SYSCALL_ENTRY0_STATE=$dirtySyscallEntry0State"
Write-Output "DIRTY_SYSCALL_ENTRY0_TOKEN=$dirtySyscallEntry0Token"
Write-Output "DIRTY_SYSCALL_ENTRY0_INVOKE_COUNT=$dirtySyscallEntry0InvokeCount"
Write-Output "DIRTY_SYSCALL_ENTRY0_LAST_ARG=$dirtySyscallEntry0LastArg"
Write-Output "DIRTY_SYSCALL_ENTRY0_LAST_RESULT=$dirtySyscallEntry0LastResult"
