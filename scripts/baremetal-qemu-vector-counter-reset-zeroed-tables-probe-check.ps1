# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-vector-counter-reset-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_VECTOR_COUNTER_RESET_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_VECTOR_COUNTER_RESET_ZEROED_TABLES_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_VECTOR_COUNTER_RESET_ZEROED_TABLES_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-vector-counter-reset-probe-check.ps1' `
    -FailureLabel 'vector-counter-reset'
$probeText = $probeState.Text


$names = @(
    'BAREMETAL_QEMU_VECTOR_COUNTER_RESET_POST_INT_VECTOR10',
    'BAREMETAL_QEMU_VECTOR_COUNTER_RESET_POST_INT_VECTOR200',
    'BAREMETAL_QEMU_VECTOR_COUNTER_RESET_POST_INT_VECTOR14',
    'BAREMETAL_QEMU_VECTOR_COUNTER_RESET_POST_EXC_VECTOR10',
    'BAREMETAL_QEMU_VECTOR_COUNTER_RESET_POST_EXC_VECTOR14'
)
foreach ($name in $names) {
    $actual = Extract-IntValue -Text $probeText -Name $name
    if ($null -eq $actual) { throw "Missing $name in vector-counter-reset output." }
    if ($actual -ne 0) { throw "Expected $name to be zero after reset, got $actual" }
}

Write-Output 'BAREMETAL_QEMU_VECTOR_COUNTER_RESET_ZEROED_TABLES_PROBE=pass'
Write-Output 'POST_INT_VECTOR10=0'
Write-Output 'POST_INT_VECTOR200=0'
Write-Output 'POST_INT_VECTOR14=0'
Write-Output 'POST_EXC_VECTOR10=0'
Write-Output 'POST_EXC_VECTOR14=0'
