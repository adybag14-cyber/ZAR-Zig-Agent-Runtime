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
    -SkippedReceipt 'BAREMETAL_QEMU_VECTOR_COUNTER_RESET_DIRTY_VECTOR_TABLE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_VECTOR_COUNTER_RESET_DIRTY_VECTOR_TABLE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-vector-counter-reset-probe-check.ps1' `
    -FailureLabel 'vector-counter-reset'
$probeText = $probeState.Text


$expect = @{
    'BAREMETAL_QEMU_VECTOR_COUNTER_RESET_PRE_INT_VECTOR10' = 2
    'BAREMETAL_QEMU_VECTOR_COUNTER_RESET_PRE_INT_VECTOR200' = 1
    'BAREMETAL_QEMU_VECTOR_COUNTER_RESET_PRE_INT_VECTOR14' = 1
    'BAREMETAL_QEMU_VECTOR_COUNTER_RESET_PRE_EXC_VECTOR10' = 2
    'BAREMETAL_QEMU_VECTOR_COUNTER_RESET_PRE_EXC_VECTOR14' = 1
}
foreach ($name in $expect.Keys) {
    $actual = Extract-IntValue -Text $probeText -Name $name
    if ($null -eq $actual) { throw "Missing $name in vector-counter-reset output." }
    if ($actual -ne $expect[$name]) { throw "Unexpected $name value: expected $($expect[$name]), got $actual" }
}

Write-Output 'BAREMETAL_QEMU_VECTOR_COUNTER_RESET_DIRTY_VECTOR_TABLE_PROBE=pass'
Write-Output 'PRE_INT_VECTOR10=2'
Write-Output 'PRE_INT_VECTOR200=1'
Write-Output 'PRE_INT_VECTOR14=1'
Write-Output 'PRE_EXC_VECTOR10=2'
Write-Output 'PRE_EXC_VECTOR14=1'
