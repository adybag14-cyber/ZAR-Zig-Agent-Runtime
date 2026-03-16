# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-masked-interrupt-timeout-probe-check.ps1"

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $pattern = '(?m)^' + [regex]::Escape($Name) + '=(-?\d+)\r?$'
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$probeOutput = if ($SkipBuild) { & $probe -SkipBuild 2>&1 } else { & $probe 2>&1 }
$probeExitCode = $LASTEXITCODE
$probeText = ($probeOutput | Out-String)
$probeOutput | Write-Output
if ($probeText -match 'BAREMETAL_QEMU_MASKED_INTERRUPT_TIMEOUT_PROBE=skipped') {
    Write-Output 'BAREMETAL_QEMU_MASKED_INTERRUPT_TIMEOUT_MASK_PRESERVE_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying masked interrupt-timeout probe failed with exit code $probeExitCode"
}

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
