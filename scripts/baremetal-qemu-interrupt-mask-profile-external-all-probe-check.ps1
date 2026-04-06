# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 40,
    [int] $GdbPort = 1348
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-interrupt-mask-profile-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_INTERRUPT_MASK_PROFILE_PROBE=skipped\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_INTERRUPT_MASK_PROFILE_EXTERNAL_ALL_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_INTERRUPT_MASK_PROFILE_EXTERNAL_ALL_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-interrupt-mask-profile-probe-check.ps1' `
    -FailureLabel 'Interrupt mask profile prerequisite' `
    -InvokeArgs @{ TimeoutSeconds = $TimeoutSeconds; GdbPort = $GdbPort }
$probeText = $probeState.Text

$task0State = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_PROFILE_PROBE_EXTERNAL_ALL_TASK0_STATE'
$wakeQueueCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_PROFILE_PROBE_EXTERNAL_ALL_WAKE_QUEUE_COUNT'
$ignoredCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_PROFILE_PROBE_EXTERNAL_ALL_IGNORED_COUNT'
$masked200 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_PROFILE_PROBE_EXTERNAL_ALL_MASKED_200'
$profile = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_PROFILE_PROBE_EXTERNAL_ALL_PROFILE'
$maskedCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_PROFILE_PROBE_EXTERNAL_ALL_MASKED_COUNT'
if ($null -in @($task0State, $wakeQueueCount, $ignoredCount, $masked200, $profile, $maskedCount)) {
    throw 'Missing expected external-all fields in probe output.'
}
if ($task0State -ne 6) { throw "Expected EXTERNAL_ALL_TASK0_STATE=6. got $task0State" }
if ($wakeQueueCount -ne 0) { throw "Expected EXTERNAL_ALL_WAKE_QUEUE_COUNT=0. got $wakeQueueCount" }
if ($ignoredCount -ne 1) { throw "Expected EXTERNAL_ALL_IGNORED_COUNT=1. got $ignoredCount" }
if ($masked200 -ne 1) { throw "Expected EXTERNAL_ALL_MASKED_200=1. got $masked200" }
if ($profile -ne 1) { throw "Expected EXTERNAL_ALL_PROFILE=1. got $profile" }
if ($maskedCount -ne 224) { throw "Expected EXTERNAL_ALL_MASKED_COUNT=224. got $maskedCount" }

Write-Output 'BAREMETAL_QEMU_INTERRUPT_MASK_PROFILE_EXTERNAL_ALL_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_INTERRUPT_MASK_PROFILE_EXTERNAL_ALL_PROBE_SOURCE=baremetal-qemu-interrupt-mask-profile-probe-check.ps1'
Write-Output "EXTERNAL_ALL_TASK0_STATE=$task0State"
Write-Output "EXTERNAL_ALL_WAKE_QUEUE_COUNT=$wakeQueueCount"
Write-Output "EXTERNAL_ALL_IGNORED_COUNT=$ignoredCount"
Write-Output "EXTERNAL_ALL_MASKED_200=$masked200"
Write-Output "EXTERNAL_ALL_PROFILE=$profile"
Write-Output "EXTERNAL_ALL_MASKED_COUNT=$maskedCount"
