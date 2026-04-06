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
    -SkippedReceipt 'BAREMETAL_QEMU_DESCRIPTOR_TABLE_CONTENT_BASELINE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_DESCRIPTOR_TABLE_CONTENT_BASELINE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-descriptor-table-content-probe-check.ps1' `
    -FailureLabel 'descriptor-table-content'
$probeText = $probeState.Text

$gdbStdout = Extract-Value -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_TABLE_CONTENT_PROBE_GDB_STDOUT'
if ([string]::IsNullOrWhiteSpace($gdbStdout) -or -not (Test-Path $gdbStdout)) {
    throw 'Missing descriptor-table-content GDB stdout log path.'
}
$rawText = Get-Content -Raw $gdbStdout

$artifact = Extract-Value -Text $probeText -Name 'BAREMETAL_QEMU_ARTIFACT'
$startAddr = Extract-Value -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_TABLE_CONTENT_PROBE_START_ADDR'
$spinPauseAddr = Extract-Value -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_TABLE_CONTENT_PROBE_SPINPAUSE_ADDR'
$gdtrAddr = Extract-Value -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_TABLE_CONTENT_PROBE_GDTR_ADDR'
$idtrAddr = Extract-Value -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_TABLE_CONTENT_PROBE_IDTR_ADDR'
$gdtAddr = Extract-Value -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_TABLE_CONTENT_PROBE_GDT_ADDR'
$idtAddr = Extract-Value -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_TABLE_CONTENT_PROBE_IDT_ADDR'
$stubAddr = Extract-Value -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_TABLE_CONTENT_PROBE_INTERRUPT_STUB_ADDR'
$hitStart = Extract-Value -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_TABLE_CONTENT_PROBE_HIT_START'
$hitAfter = Extract-Value -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_TABLE_CONTENT_PROBE_HIT_AFTER_DESCRIPTOR_TABLE_CONTENT'
$ack = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_TABLE_CONTENT_PROBE_ACK'
$lastOpcode = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_TABLE_CONTENT_PROBE_LAST_OPCODE'
$lastResult = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_TABLE_CONTENT_PROBE_LAST_RESULT'
$ticks = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_TABLE_CONTENT_PROBE_TICKS'
$readyBefore = Extract-Field -BroadText $probeText -RawText $rawText -Name 'DESCRIPTOR_READY_BEFORE'
$loadedBefore = Extract-Field -BroadText $probeText -RawText $rawText -Name 'DESCRIPTOR_LOADED_BEFORE'
$readyAfter = Extract-Field -BroadText $probeText -RawText $rawText -Name 'DESCRIPTOR_READY_AFTER_REINIT'
$loadedAfter = Extract-Field -BroadText $probeText -RawText $rawText -Name 'DESCRIPTOR_LOADED_AFTER_REINIT'
$readyFinal = Extract-Field -BroadText $probeText -RawText $rawText -Name 'DESCRIPTOR_READY_FINAL'
$loadedFinal = Extract-Field -BroadText $probeText -RawText $rawText -Name 'DESCRIPTOR_LOADED_FINAL'

if ($null -in @($artifact, $startAddr, $spinPauseAddr, $gdtrAddr, $idtrAddr, $gdtAddr, $idtAddr, $stubAddr, $hitStart, $hitAfter, $ack, $lastOpcode, $lastResult, $ticks, $readyBefore, $loadedBefore, $readyAfter, $loadedAfter, $readyFinal, $loadedFinal)) {
    throw 'Missing descriptor-table-content baseline fields.'
}
if ($hitStart -ne 'True' -or $hitAfter -ne 'True') {
    throw 'Descriptor-table-content baseline expected both HIT_START and HIT_AFTER_DESCRIPTOR_TABLE_CONTENT.'
}
if ($ack -ne 2 -or $lastOpcode -ne 10 -or $lastResult -ne 0) {
    throw "Unexpected baseline mailbox state: ack=$ack opcode=$lastOpcode result=$lastResult"
}
if ($ticks -le 0) {
    throw "Expected TICKS>0. got $ticks"
}
if ($readyBefore -ne 1 -or $loadedBefore -ne 1 -or $readyAfter -ne 1 -or $loadedAfter -ne 1 -or $readyFinal -ne 1 -or $loadedFinal -ne 1) {
    throw 'Descriptor-table-content readiness/load baseline drifted.'
}

Write-Output 'BAREMETAL_QEMU_DESCRIPTOR_TABLE_CONTENT_BASELINE_PROBE=pass'
Write-Output "ARTIFACT=$artifact"
Write-Output "ACK=$ack"
Write-Output "LAST_OPCODE=$lastOpcode"
Write-Output "LAST_RESULT=$lastResult"
Write-Output "TICKS=$ticks"
