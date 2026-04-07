# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-interrupt-mask-control-probe-check.ps1"

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_INVALID_PRESERVE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_INVALID_PRESERVE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-interrupt-mask-control-probe-check.ps1' `
    -FailureLabel 'interrupt-mask-control'
$probeText = $probeState.Text

$invalidVectorResult = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_INVALID_VECTOR_RESULT'
$invalidVectorProfile = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_INVALID_VECTOR_CURRENT_PROFILE'
$invalidVectorMaskedCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_INVALID_VECTOR_CURRENT_MASKED_COUNT'
$invalidVectorMasked200 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_INVALID_VECTOR_CURRENT_MASKED_200'
$invalidStateResult = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_INVALID_STATE_RESULT'
$invalidStateProfile = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_INVALID_STATE_CURRENT_PROFILE'
$invalidStateMaskedCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_INVALID_STATE_CURRENT_MASKED_COUNT'
$invalidStateMasked200 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_INVALID_STATE_CURRENT_MASKED_200'
if ($null -in @($invalidVectorResult, $invalidVectorProfile, $invalidVectorMaskedCount, $invalidVectorMasked200, $invalidStateResult, $invalidStateProfile, $invalidStateMaskedCount, $invalidStateMasked200)) {
    throw 'Missing invalid-preserve fields in interrupt-mask-control probe output.'
}
if ($invalidVectorResult -ne -22) { throw "Expected INVALID_VECTOR_RESULT=-22, got $invalidVectorResult" }
if ($invalidVectorProfile -ne 255) { throw "Expected INVALID_VECTOR_CURRENT_PROFILE=255, got $invalidVectorProfile" }
if ($invalidVectorMaskedCount -ne 0) { throw "Expected INVALID_VECTOR_CURRENT_MASKED_COUNT=0, got $invalidVectorMaskedCount" }
if ($invalidVectorMasked200 -ne 0) { throw "Expected INVALID_VECTOR_CURRENT_MASKED_200=0, got $invalidVectorMasked200" }
if ($invalidStateResult -ne -22) { throw "Expected INVALID_STATE_RESULT=-22, got $invalidStateResult" }
if ($invalidStateProfile -ne 255) { throw "Expected INVALID_STATE_CURRENT_PROFILE=255, got $invalidStateProfile" }
if ($invalidStateMaskedCount -ne 0) { throw "Expected INVALID_STATE_CURRENT_MASKED_COUNT=0, got $invalidStateMaskedCount" }
if ($invalidStateMasked200 -ne 0) { throw "Expected INVALID_STATE_CURRENT_MASKED_200=0, got $invalidStateMasked200" }

Write-Output 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_INVALID_PRESERVE_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_INVALID_PRESERVE_PROBE_SOURCE=baremetal-qemu-interrupt-mask-control-probe-check.ps1'
Write-Output "INVALID_VECTOR_RESULT=$invalidVectorResult"
Write-Output "INVALID_VECTOR_CURRENT_PROFILE=$invalidVectorProfile"
Write-Output "INVALID_VECTOR_CURRENT_MASKED_COUNT=$invalidVectorMaskedCount"
Write-Output "INVALID_VECTOR_CURRENT_MASKED_200=$invalidVectorMasked200"
Write-Output "INVALID_STATE_RESULT=$invalidStateResult"
Write-Output "INVALID_STATE_CURRENT_PROFILE=$invalidStateProfile"
Write-Output "INVALID_STATE_CURRENT_MASKED_COUNT=$invalidStateMaskedCount"
Write-Output "INVALID_STATE_CURRENT_MASKED_200=$invalidStateMasked200"
