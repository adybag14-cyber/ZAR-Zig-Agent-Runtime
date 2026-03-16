# SPDX-License-Identifier: GPL-2.0-only
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
    Write-Output 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_RESET_IGNORED_PROBE=skipped'
    Write-Output 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_RESET_IGNORED_PROBE_SOURCE=baremetal-qemu-interrupt-mask-control-probe-check.ps1'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying interrupt-mask-control probe failed with exit code $probeExitCode"
}

$secondaryMaskedCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_SECONDARY_MASKED_COUNT'
$secondaryIgnoredCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_SECONDARY_IGNORED_COUNT'
$resetIgnoredCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_RESET_IGNORED_COUNT'
$resetIgnored200 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_RESET_IGNORED_200'
$resetIgnored201 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_RESET_IGNORED_201'
$resetLastMaskedVector = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_RESET_LAST_MASKED_VECTOR'
if ($null -in @($secondaryMaskedCount, $secondaryIgnoredCount, $resetIgnoredCount, $resetIgnored200, $resetIgnored201, $resetLastMaskedVector)) {
    throw 'Missing reset-ignored fields in interrupt-mask-control probe output.'
}
if ($secondaryMaskedCount -ne 1) { throw "Expected SECONDARY_MASKED_COUNT=1, got $secondaryMaskedCount" }
if ($secondaryIgnoredCount -ne 2) { throw "Expected SECONDARY_IGNORED_COUNT=2, got $secondaryIgnoredCount" }
if ($resetIgnoredCount -ne 0) { throw "Expected RESET_IGNORED_COUNT=0, got $resetIgnoredCount" }
if ($resetIgnored200 -ne 0) { throw "Expected RESET_IGNORED_200=0, got $resetIgnored200" }
if ($resetIgnored201 -ne 0) { throw "Expected RESET_IGNORED_201=0, got $resetIgnored201" }
if ($resetLastMaskedVector -ne 0) { throw "Expected RESET_LAST_MASKED_VECTOR=0, got $resetLastMaskedVector" }

Write-Output 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_RESET_IGNORED_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_RESET_IGNORED_PROBE_SOURCE=baremetal-qemu-interrupt-mask-control-probe-check.ps1'
Write-Output "SECONDARY_MASKED_COUNT=$secondaryMaskedCount"
Write-Output "SECONDARY_IGNORED_COUNT=$secondaryIgnoredCount"
Write-Output "RESET_IGNORED_COUNT=$resetIgnoredCount"
Write-Output "RESET_IGNORED_200=$resetIgnored200"
Write-Output "RESET_IGNORED_201=$resetIgnored201"
Write-Output "RESET_LAST_MASKED_VECTOR=$resetLastMaskedVector"
