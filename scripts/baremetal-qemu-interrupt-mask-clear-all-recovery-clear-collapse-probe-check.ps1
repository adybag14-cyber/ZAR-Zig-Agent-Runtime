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
    -SkippedReceipt 'BAREMETAL_QEMU_INTERRUPT_MASK_CLEAR_ALL_RECOVERY_CLEAR_COLLAPSE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_INTERRUPT_MASK_CLEAR_ALL_RECOVERY_CLEAR_COLLAPSE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-interrupt-mask-clear-all-recovery-probe-check.ps1' `
    -FailureLabel 'interrupt-mask-clear-all-recovery'
$probeText = $probeState.Text

$profile = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_INTERRUPT_MASK_PROFILE'
$maskedCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_INTERRUPT_MASKED_COUNT'
$ignoredCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_MASKED_INTERRUPT_IGNORED_COUNT'
$ignored200 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_MASKED_VECTOR_200_IGNORED'
$lastMaskedVector = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_LAST_MASKED_INTERRUPT_VECTOR'
if ($null -in @($profile, $maskedCount, $ignoredCount, $ignored200, $lastMaskedVector)) {
    throw 'Missing clear-collapse fields in interrupt-mask-clear-all-recovery probe output.'
}
if ($profile -ne 0) { throw "Expected INTERRUPT_MASK_PROFILE=0, got $profile" }
if ($maskedCount -ne 0) { throw "Expected INTERRUPT_MASKED_COUNT=0, got $maskedCount" }
if ($ignoredCount -ne 0) { throw "Expected MASKED_INTERRUPT_IGNORED_COUNT=0, got $ignoredCount" }
if ($ignored200 -ne 0) { throw "Expected MASKED_VECTOR_200_IGNORED=0, got $ignored200" }
if ($lastMaskedVector -ne 0) { throw "Expected LAST_MASKED_INTERRUPT_VECTOR=0, got $lastMaskedVector" }
Write-Output 'BAREMETAL_QEMU_INTERRUPT_MASK_CLEAR_ALL_RECOVERY_CLEAR_COLLAPSE_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_INTERRUPT_MASK_CLEAR_ALL_RECOVERY_CLEAR_COLLAPSE_PROBE_SOURCE=baremetal-qemu-interrupt-mask-clear-all-recovery-probe-check.ps1'
Write-Output "INTERRUPT_MASK_PROFILE=$profile"
Write-Output "INTERRUPT_MASKED_COUNT=$maskedCount"
Write-Output "MASKED_INTERRUPT_IGNORED_COUNT=$ignoredCount"
Write-Output "MASKED_VECTOR_200_IGNORED=$ignored200"
Write-Output "LAST_MASKED_INTERRUPT_VECTOR=$lastMaskedVector"
