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
    -SkippedReceipt 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_RESET_POST_RESET_SYSCALL_BASELINE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_RESET_POST_RESET_SYSCALL_BASELINE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-allocator-syscall-reset-probe-check.ps1' `
    -FailureLabel 'allocator-syscall-reset'
$probeText = $probeState.Text

$postSyscallEnabled = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_RESET_PROBE_POST_SYSCALL_ENABLED'
$postSyscallEntryCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_RESET_PROBE_POST_SYSCALL_ENTRY_COUNT'
$postSyscallLastId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_RESET_PROBE_POST_SYSCALL_LAST_ID'
$postSyscallDispatchCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_RESET_PROBE_POST_SYSCALL_DISPATCH_COUNT'
$postSyscallLastInvokeTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_RESET_PROBE_POST_SYSCALL_LAST_INVOKE_TICK'
$postSyscallLastResult = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_RESET_PROBE_POST_SYSCALL_LAST_RESULT'
$postSyscallEntry0State = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_RESET_PROBE_POST_SYSCALL_ENTRY0_STATE'

if ($null -in @($postSyscallEnabled, $postSyscallEntryCount, $postSyscallLastId, $postSyscallDispatchCount, $postSyscallLastInvokeTick, $postSyscallLastResult, $postSyscallEntry0State)) {
    throw 'Missing expected post-reset syscall fields in allocator-syscall-reset probe output.'
}
if ($postSyscallEnabled -ne 1) { throw "Expected POST_SYSCALL_ENABLED=1. got $postSyscallEnabled" }
if ($postSyscallEntryCount -ne 0) { throw "Expected POST_SYSCALL_ENTRY_COUNT=0. got $postSyscallEntryCount" }
if ($postSyscallLastId -ne 0) { throw "Expected POST_SYSCALL_LAST_ID=0. got $postSyscallLastId" }
if ($postSyscallDispatchCount -ne 0) { throw "Expected POST_SYSCALL_DISPATCH_COUNT=0. got $postSyscallDispatchCount" }
if ($postSyscallLastInvokeTick -ne 0) { throw "Expected POST_SYSCALL_LAST_INVOKE_TICK=0. got $postSyscallLastInvokeTick" }
if ($postSyscallLastResult -ne 0) { throw "Expected POST_SYSCALL_LAST_RESULT=0. got $postSyscallLastResult" }
if ($postSyscallEntry0State -ne 0) { throw "Expected POST_SYSCALL_ENTRY0_STATE=0. got $postSyscallEntry0State" }

Write-Output 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_RESET_POST_RESET_SYSCALL_BASELINE_PROBE=pass'
Write-Output "POST_SYSCALL_ENABLED=$postSyscallEnabled"
Write-Output "POST_SYSCALL_ENTRY_COUNT=$postSyscallEntryCount"
Write-Output "POST_SYSCALL_LAST_ID=$postSyscallLastId"
Write-Output "POST_SYSCALL_DISPATCH_COUNT=$postSyscallDispatchCount"
Write-Output "POST_SYSCALL_LAST_INVOKE_TICK=$postSyscallLastInvokeTick"
Write-Output "POST_SYSCALL_LAST_RESULT=$postSyscallLastResult"
Write-Output "POST_SYSCALL_ENTRY0_STATE=$postSyscallEntry0State"
