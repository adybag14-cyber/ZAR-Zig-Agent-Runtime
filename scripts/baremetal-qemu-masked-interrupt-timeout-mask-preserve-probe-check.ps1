# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-masked-interrupt-timeout-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_MASKED_INTERRUPT_TIMEOUT_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_MASKED_INTERRUPT_TIMEOUT_MASK_PRESERVE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_MASKED_INTERRUPT_TIMEOUT_MASK_PRESERVE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-masked-interrupt-timeout-probe-check.ps1' `
    -FailureLabel 'masked-interrupt-timeout'
$probeText = $probeState.Text


$profileAfterInterrupt = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MASKED_INTERRUPT_TIMEOUT_PROBE_PROFILE_AFTER_INTERRUPT'
$interruptMaskProfile = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MASKED_INTERRUPT_TIMEOUT_PROBE_INTERRUPT_MASK_PROFILE'
$lastMaskedVectorAfterInterrupt = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MASKED_INTERRUPT_TIMEOUT_PROBE_LAST_MASKED_VECTOR_AFTER_INTERRUPT'
$lastMaskedInterruptVector = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MASKED_INTERRUPT_TIMEOUT_PROBE_LAST_MASKED_INTERRUPT_VECTOR'
if ($null -in @($profileAfterInterrupt, $interruptMaskProfile, $lastMaskedVectorAfterInterrupt, $lastMaskedInterruptVector)) {
    throw 'Missing mask-preserve fields in probe output.'
}
if ($profileAfterInterrupt -ne 1) { throw "Expected masked-stage profile external_all (1). got $profileAfterInterrupt" }
if ($interruptMaskProfile -ne 1) { throw "Expected final profile external_all (1). got $interruptMaskProfile" }
if ($lastMaskedVectorAfterInterrupt -ne 200) { throw "Expected masked-stage last masked vector 200. got $lastMaskedVectorAfterInterrupt" }
if ($lastMaskedInterruptVector -ne 200) { throw "Expected final last masked vector 200. got $lastMaskedInterruptVector" }

Write-Output 'BAREMETAL_QEMU_MASKED_INTERRUPT_TIMEOUT_MASK_PRESERVE_PROBE=pass'
Write-Output "PROFILE_AFTER_INTERRUPT=$profileAfterInterrupt"
Write-Output "INTERRUPT_MASK_PROFILE=$interruptMaskProfile"
Write-Output "LAST_MASKED_VECTOR_AFTER_INTERRUPT=$lastMaskedVectorAfterInterrupt"
Write-Output "LAST_MASKED_INTERRUPT_VECTOR=$lastMaskedInterruptVector"
