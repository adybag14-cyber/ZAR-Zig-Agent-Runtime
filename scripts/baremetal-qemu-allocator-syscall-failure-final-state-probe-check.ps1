# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 30,
    [int] $GdbPort = 0
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-allocator-syscall-failure-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$invoke = @{ TimeoutSeconds = $TimeoutSeconds }
if ($GdbPort -gt 0) { $invoke.GdbPort = $GdbPort }
$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_ALLOCATOR_SYSCALL_FAILURE_PROBE=skipped\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_FAILURE_FINAL_STATE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_FAILURE_FINAL_STATE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-allocator-syscall-failure-probe-check.ps1' `
    -FailureLabel 'allocator/syscall failure' `
    -InvokeArgs $invoke
$probeText = $probeState.Text

$expected = @{
    'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_FAILURE_PROBE_LAST_RESULT' = -38
    'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_FAILURE_PROBE_COMMAND_RESULT_OK_COUNT' = 4
    'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_FAILURE_PROBE_COMMAND_RESULT_INVALID_COUNT' = 1
    'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_FAILURE_PROBE_COMMAND_RESULT_NOT_SUPPORTED_COUNT' = 1
    'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_FAILURE_PROBE_COMMAND_RESULT_OTHER_ERROR_COUNT' = 2
    'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_FAILURE_PROBE_COMMAND_RESULT_TOTAL_COUNT' = 8
    'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_FAILURE_PROBE_SYSCALL_ENABLED' = 0
    'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_FAILURE_PROBE_SYSCALL_ENTRY0_STATE' = 1
    'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_FAILURE_PROBE_SYSCALL_ENTRY0_TOKEN' = 48879
}

foreach ($entry in $expected.GetEnumerator()) {
    $actual = Extract-IntValue -Text $probeText -Name $entry.Key
    if ($null -eq $actual) { throw "Missing output value for $($entry.Key)" }
    if ($actual -ne $entry.Value) { throw "Unexpected $($entry.Key): got $actual expected $($entry.Value)" }
}

Write-Output 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_FAILURE_FINAL_STATE_PROBE=pass'
Write-Output 'LAST_RESULT=-38'
Write-Output 'COMMAND_RESULT_OK_COUNT=4'
Write-Output 'COMMAND_RESULT_INVALID_COUNT=1'
Write-Output 'COMMAND_RESULT_NOT_SUPPORTED_COUNT=1'
Write-Output 'COMMAND_RESULT_OTHER_ERROR_COUNT=2'
Write-Output 'COMMAND_RESULT_TOTAL_COUNT=8'
Write-Output 'SYSCALL_ENABLED=0'
Write-Output 'SYSCALL_ENTRY0_STATE=1'
Write-Output 'SYSCALL_ENTRY0_TOKEN=48879'
