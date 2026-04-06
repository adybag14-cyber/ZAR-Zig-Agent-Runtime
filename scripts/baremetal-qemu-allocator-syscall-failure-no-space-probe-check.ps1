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
    -SkippedReceipt 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_FAILURE_NO_SPACE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_FAILURE_NO_SPACE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-allocator-syscall-failure-probe-check.ps1' `
    -FailureLabel 'allocator/syscall failure' `
    -InvokeArgs $invoke
$probeText = $probeState.Text

$expected = @{
    'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_FAILURE_PROBE_NO_SPACE_RESULT' = -28
    'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_FAILURE_PROBE_ALLOCATOR_FREE_PAGES_AFTER_FAILURE' = 256
    'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_FAILURE_PROBE_ALLOCATOR_ALLOCATION_COUNT_AFTER_FAILURE' = 0
    'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_FAILURE_PROBE_ALLOCATOR_BYTES_IN_USE_AFTER_FAILURE' = 0
}

foreach ($entry in $expected.GetEnumerator()) {
    $actual = Extract-IntValue -Text $probeText -Name $entry.Key
    if ($null -eq $actual) { throw "Missing output value for $($entry.Key)" }
    if ($actual -ne $entry.Value) { throw "Unexpected $($entry.Key): got $actual expected $($entry.Value)" }
}

Write-Output 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_FAILURE_NO_SPACE_PROBE=pass'
Write-Output 'NO_SPACE_RESULT=-28'
Write-Output 'ALLOCATOR_FREE_PAGES_AFTER_FAILURE=256'
Write-Output 'ALLOCATOR_ALLOCATION_COUNT_AFTER_FAILURE=0'
Write-Output 'ALLOCATOR_BYTES_IN_USE_AFTER_FAILURE=0'
