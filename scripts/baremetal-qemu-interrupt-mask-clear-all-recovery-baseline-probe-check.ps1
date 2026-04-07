# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-interrupt-mask-clear-all-recovery-probe-check.ps1"

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_INTERRUPT_MASK_CLEAR_ALL_RECOVERY_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_INTERRUPT_MASK_CLEAR_ALL_RECOVERY_BASELINE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_INTERRUPT_MASK_CLEAR_ALL_RECOVERY_BASELINE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-interrupt-mask-clear-all-recovery-probe-check.ps1' `
    -FailureLabel 'interrupt-mask-clear-all-recovery'
$probeText = $probeState.Text

$task0State = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_SET_MASKED_TASK0_STATE'
$wakeQueueCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_SET_MASKED_WAKE_QUEUE_COUNT'
$ignoredCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_SET_MASKED_IGNORED_COUNT'
$profile = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_SET_MASKED_PROFILE'
$maskedCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_SET_MASKED_MASKED_COUNT'
$lastMaskedVector = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_SET_MASKED_LAST_MASKED_VECTOR'
if ($null -in @($task0State, $wakeQueueCount, $ignoredCount, $profile, $maskedCount, $lastMaskedVector)) {
    throw 'Missing baseline fields in interrupt-mask-clear-all-recovery probe output.'
}
if ($task0State -ne 6) { throw "Expected SET_MASKED_TASK0_STATE=6, got $task0State" }
if ($wakeQueueCount -ne 0) { throw "Expected SET_MASKED_WAKE_QUEUE_COUNT=0, got $wakeQueueCount" }
if ($ignoredCount -ne 1) { throw "Expected SET_MASKED_IGNORED_COUNT=1, got $ignoredCount" }
if ($profile -ne 255) { throw "Expected SET_MASKED_PROFILE=255, got $profile" }
if ($maskedCount -ne 1) { throw "Expected SET_MASKED_MASKED_COUNT=1, got $maskedCount" }
if ($lastMaskedVector -ne 200) { throw "Expected SET_MASKED_LAST_MASKED_VECTOR=200, got $lastMaskedVector" }
Write-Output 'BAREMETAL_QEMU_INTERRUPT_MASK_CLEAR_ALL_RECOVERY_BASELINE_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_INTERRUPT_MASK_CLEAR_ALL_RECOVERY_BASELINE_PROBE_SOURCE=baremetal-qemu-interrupt-mask-clear-all-recovery-probe-check.ps1'
Write-Output "SET_MASKED_TASK0_STATE=$task0State"
Write-Output "SET_MASKED_WAKE_QUEUE_COUNT=$wakeQueueCount"
Write-Output "SET_MASKED_IGNORED_COUNT=$ignoredCount"
Write-Output "SET_MASKED_PROFILE=$profile"
Write-Output "SET_MASKED_MASKED_COUNT=$maskedCount"
Write-Output "SET_MASKED_LAST_MASKED_VECTOR=$lastMaskedVector"
