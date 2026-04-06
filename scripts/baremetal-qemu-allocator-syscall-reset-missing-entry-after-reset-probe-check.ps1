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
    -SkippedReceipt 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_RESET_MISSING_ENTRY_AFTER_RESET_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_RESET_MISSING_ENTRY_AFTER_RESET_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-allocator-syscall-reset-probe-check.ps1' `
    -FailureLabel 'allocator-syscall-reset'
$probeText = $probeState.Text

$ack = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_RESET_PROBE_ACK'
$lastOpcode = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_RESET_PROBE_LAST_OPCODE'
$lastResult = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_RESET_PROBE_LAST_RESULT'
$mode = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_RESET_PROBE_MODE'
$ticks = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_RESET_PROBE_TICKS'

if ($null -in @($ack, $lastOpcode, $lastResult, $mode, $ticks)) {
    throw 'Missing expected final missing-entry receipt fields in allocator-syscall-reset probe output.'
}
if ($ack -ne 8) { throw "Expected ACK=8. got $ack" }
if ($lastOpcode -ne 36) { throw "Expected LAST_OPCODE=36. got $lastOpcode" }
if ($lastResult -ne -2) { throw "Expected LAST_RESULT=-2. got $lastResult" }
if ($mode -ne 1) { throw "Expected MODE=1. got $mode" }
if ($ticks -lt 8) { throw "Expected TICKS >= 8. got $ticks" }

Write-Output 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_RESET_MISSING_ENTRY_AFTER_RESET_PROBE=pass'
Write-Output "ACK=$ack"
Write-Output "LAST_OPCODE=$lastOpcode"
Write-Output "LAST_RESULT=$lastResult"
Write-Output "MODE=$mode"
Write-Output "TICKS=$ticks"
