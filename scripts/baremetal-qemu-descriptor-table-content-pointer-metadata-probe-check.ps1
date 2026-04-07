# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-descriptor-table-content-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_DESCRIPTOR_TABLE_CONTENT_PROBE=skipped\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_DESCRIPTOR_TABLE_CONTENT_POINTER_METADATA_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_DESCRIPTOR_TABLE_CONTENT_POINTER_METADATA_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-descriptor-table-content-probe-check.ps1' `
    -FailureLabel 'descriptor-table-content'
$probeText = $probeState.Text

$gdbStdout = Extract-Value -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_TABLE_CONTENT_PROBE_GDB_STDOUT'
if ([string]::IsNullOrWhiteSpace($gdbStdout) -or -not (Test-Path $gdbStdout)) {
    throw 'Missing descriptor-table-content GDB stdout log path.'
}
$rawText = Get-Content -Raw $gdbStdout

$gdtrLimit = Extract-Field -BroadText $probeText -RawText $rawText -Name 'GDTR_LIMIT'
$idtrLimit = Extract-Field -BroadText $probeText -RawText $rawText -Name 'IDTR_LIMIT'
$gdtrBase = Extract-Field -BroadText $probeText -RawText $rawText -Name 'GDTR_BASE'
$idtrBase = Extract-Field -BroadText $probeText -RawText $rawText -Name 'IDTR_BASE'
$gdtSymbol = Extract-Field -BroadText $probeText -RawText $rawText -Name 'GDT_SYMBOL'
$idtSymbol = Extract-Field -BroadText $probeText -RawText $rawText -Name 'IDT_SYMBOL'

if ($null -in @($gdtrLimit, $idtrLimit, $gdtrBase, $idtrBase, $gdtSymbol, $idtSymbol)) {
    throw 'Missing descriptor pointer metadata fields.'
}
if ($gdtrLimit -ne 63) {
    throw "Expected GDTR_LIMIT=63. got $gdtrLimit"
}
if ($idtrLimit -ne 4095) {
    throw "Expected IDTR_LIMIT=4095. got $idtrLimit"
}
if ($gdtrBase -ne $gdtSymbol) {
    throw "Expected GDTR_BASE==GDT_SYMBOL. got $gdtrBase vs $gdtSymbol"
}
if ($idtrBase -ne $idtSymbol) {
    throw "Expected IDTR_BASE==IDT_SYMBOL. got $idtrBase vs $idtSymbol"
}

Write-Output 'BAREMETAL_QEMU_DESCRIPTOR_TABLE_CONTENT_POINTER_METADATA_PROBE=pass'
Write-Output "GDTR_LIMIT=$gdtrLimit"
Write-Output "IDTR_LIMIT=$idtrLimit"
Write-Output "GDTR_BASE=$gdtrBase"
Write-Output "IDTR_BASE=$idtrBase"
