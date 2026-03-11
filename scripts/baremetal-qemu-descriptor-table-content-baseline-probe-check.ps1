param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-descriptor-table-content-probe-check.ps1"

function Extract-Value {
    param([string] $Text, [string] $Name)
    $pattern = '(?m)^' + [regex]::Escape($Name) + '=(.+)\r?$'
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { return $null }
    return $match.Groups[1].Value.Trim()
}

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $pattern = '(?m)^' + [regex]::Escape($Name) + '=(-?\d+)\r?$'
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

function Extract-Field {
    param([string] $BroadText, [string] $RawText, [string] $Name)
    $value = Extract-IntValue -Text $BroadText -Name $Name
    if ($null -ne $value) { return $value }
    return Extract-IntValue -Text $RawText -Name $Name
}

$probeOutput = if ($SkipBuild) { & $probe -SkipBuild 2>&1 } else { & $probe 2>&1 }
$probeExitCode = $LASTEXITCODE
$probeText = ($probeOutput | Out-String)
$probeOutput | Write-Output
if ($probeText -match 'BAREMETAL_QEMU_DESCRIPTOR_TABLE_CONTENT_PROBE=skipped') {
    Write-Output 'BAREMETAL_QEMU_DESCRIPTOR_TABLE_CONTENT_BASELINE_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying descriptor-table-content probe failed with exit code $probeExitCode"
}

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
