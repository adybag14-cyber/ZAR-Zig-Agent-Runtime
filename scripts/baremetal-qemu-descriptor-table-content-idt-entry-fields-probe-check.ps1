param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-descriptor-table-content-probe-check.ps1"

function Extract-Value {
    param([string] $Text, [string] $Name)
    $pattern = '(?m)^' + [regex]::Escape($Name) + '=(.+?)\r?$'
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
    Write-Output 'BAREMETAL_QEMU_DESCRIPTOR_TABLE_CONTENT_IDT_ENTRY_FIELDS_PROBE=skipped'
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

$idt0Selector = Extract-Field -BroadText $probeText -RawText $rawText -Name 'IDT0_SELECTOR'
$idt0Ist = Extract-Field -BroadText $probeText -RawText $rawText -Name 'IDT0_IST'
$idt0TypeAttr = Extract-Field -BroadText $probeText -RawText $rawText -Name 'IDT0_TYPE_ATTR'
$idt0Zero = Extract-Field -BroadText $probeText -RawText $rawText -Name 'IDT0_ZERO'
$idt255Selector = Extract-Field -BroadText $probeText -RawText $rawText -Name 'IDT255_SELECTOR'
$idt255Ist = Extract-Field -BroadText $probeText -RawText $rawText -Name 'IDT255_IST'
$idt255TypeAttr = Extract-Field -BroadText $probeText -RawText $rawText -Name 'IDT255_TYPE_ATTR'
$idt255Zero = Extract-Field -BroadText $probeText -RawText $rawText -Name 'IDT255_ZERO'

if ($null -in @($idt0Selector, $idt0Ist, $idt0TypeAttr, $idt0Zero, $idt255Selector, $idt255Ist, $idt255TypeAttr, $idt255Zero)) {
    throw 'Missing IDT entry fields.'
}
if ($idt0Selector -ne 8 -or $idt0Ist -ne 0 -or $idt0TypeAttr -ne 142 -or $idt0Zero -ne 0) {
    throw 'Unexpected IDT[0] entry fields.'
}
if ($idt255Selector -ne 8 -or $idt255Ist -ne 0 -or $idt255TypeAttr -ne 142 -or $idt255Zero -ne 0) {
    throw 'Unexpected IDT[255] entry fields.'
}

Write-Output 'BAREMETAL_QEMU_DESCRIPTOR_TABLE_CONTENT_IDT_ENTRY_FIELDS_PROBE=pass'
Write-Output "IDT0_SELECTOR=$idt0Selector"
Write-Output "IDT255_SELECTOR=$idt255Selector"
Write-Output "IDT0_TYPE_ATTR=$idt0TypeAttr"
Write-Output "IDT255_TYPE_ATTR=$idt255TypeAttr"
