param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-interrupt-mask-control-probe-check.ps1"

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $match = [regex]::Match($Text, '(?m)^' + [regex]::Escape($Name) + '=(-?\d+)\r?$')
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$probeOutput = if ($SkipBuild) { & $probe -SkipBuild 2>&1 } else { & $probe 2>&1 }
$probeExitCode = $LASTEXITCODE
$probeText = ($probeOutput | Out-String)
$probeOutput | Write-Output
if ($probeText -match '(?m)^BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE=skipped\r?$') {
    Write-Output 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_FINAL_STATE_PROBE=skipped'
    Write-Output 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_FINAL_STATE_PROBE_SOURCE=baremetal-qemu-interrupt-mask-control-probe-check.ps1'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying interrupt-mask-control probe failed with exit code $probeExitCode"
}

$profile = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_INTERRUPT_MASK_PROFILE'
$maskedCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_INTERRUPT_MASKED_COUNT'
$ignoredCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_MASKED_INTERRUPT_IGNORED_COUNT'
$masked200 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_MASKED_VECTOR_200_IGNORED'
$masked201 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_MASKED_VECTOR_201_IGNORED'
$lastMaskedVector = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_LAST_MASKED_INTERRUPT_VECTOR'
$wakeQueueCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_WAKE_QUEUE_COUNT'
$wake0Vector = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_WAKE0_VECTOR'
$wake0Reason = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_WAKE0_REASON'
if ($null -in @($profile, $maskedCount, $ignoredCount, $masked200, $masked201, $lastMaskedVector, $wakeQueueCount, $wake0Vector, $wake0Reason)) {
    throw 'Missing final-state fields in interrupt-mask-control probe output.'
}
if ($profile -ne 0) { throw "Expected INTERRUPT_MASK_PROFILE=0, got $profile" }
if ($maskedCount -ne 0) { throw "Expected INTERRUPT_MASKED_COUNT=0, got $maskedCount" }
if ($ignoredCount -ne 0) { throw "Expected MASKED_INTERRUPT_IGNORED_COUNT=0, got $ignoredCount" }
if ($masked200 -ne 0) { throw "Expected MASKED_VECTOR_200_IGNORED=0, got $masked200" }
if ($masked201 -ne 0) { throw "Expected MASKED_VECTOR_201_IGNORED=0, got $masked201" }
if ($lastMaskedVector -ne 0) { throw "Expected LAST_MASKED_INTERRUPT_VECTOR=0, got $lastMaskedVector" }
if ($wakeQueueCount -ne 1) { throw "Expected WAKE_QUEUE_COUNT=1, got $wakeQueueCount" }
if ($wake0Vector -ne 200) { throw "Expected WAKE0_VECTOR=200, got $wake0Vector" }
if ($wake0Reason -ne 2) { throw "Expected WAKE0_REASON=2, got $wake0Reason" }

Write-Output 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_FINAL_STATE_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_FINAL_STATE_PROBE_SOURCE=baremetal-qemu-interrupt-mask-control-probe-check.ps1'
Write-Output "INTERRUPT_MASK_PROFILE=$profile"
Write-Output "INTERRUPT_MASKED_COUNT=$maskedCount"
Write-Output "MASKED_INTERRUPT_IGNORED_COUNT=$ignoredCount"
Write-Output "MASKED_VECTOR_200_IGNORED=$masked200"
Write-Output "MASKED_VECTOR_201_IGNORED=$masked201"
Write-Output "LAST_MASKED_INTERRUPT_VECTOR=$lastMaskedVector"
Write-Output "WAKE_QUEUE_COUNT=$wakeQueueCount"
Write-Output "WAKE0_VECTOR=$wake0Vector"
Write-Output "WAKE0_REASON=$wake0Reason"
