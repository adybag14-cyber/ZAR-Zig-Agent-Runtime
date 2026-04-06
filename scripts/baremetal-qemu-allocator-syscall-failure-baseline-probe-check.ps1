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
    -SkippedReceipt 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_FAILURE_BASELINE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_FAILURE_BASELINE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-allocator-syscall-failure-probe-check.ps1' `
    -FailureLabel 'allocator/syscall failure' `
    -InvokeArgs $invoke
$probeText = $probeState.Text

$expected = @{
    'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_FAILURE_PROBE_ACK' = 11
    'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_FAILURE_PROBE_LAST_OPCODE' = 36
    'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_FAILURE_PROBE_LAST_RESULT' = -38
    'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_FAILURE_PROBE_MAILBOX_OPCODE' = 36
    'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_FAILURE_PROBE_MAILBOX_SEQ' = 11
}

foreach ($entry in $expected.GetEnumerator()) {
    $actual = Extract-IntValue -Text $probeText -Name $entry.Key
    if ($null -eq $actual) { throw "Missing output value for $($entry.Key)" }
    if ($actual -ne $entry.Value) { throw "Unexpected $($entry.Key): got $actual expected $($entry.Value)" }
}

$ticks = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_FAILURE_PROBE_TICKS'
if ($null -eq $ticks) { throw 'Missing output value for TICKS' }
if ($ticks -lt 10) { throw "Unexpected TICKS: got $ticks expected at least 10" }

Write-Output 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_FAILURE_BASELINE_PROBE=pass'
Write-Output 'ACK=11'
Write-Output 'LAST_OPCODE=36'
Write-Output 'LAST_RESULT=-38'
Write-Output 'MAILBOX_OPCODE=36'
Write-Output 'MAILBOX_SEQ=11'
Write-Output "TICKS=$ticks"
