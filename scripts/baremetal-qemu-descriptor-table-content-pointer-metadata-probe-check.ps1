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
    Write-Output 'BAREMETAL_QEMU_DESCRIPTOR_TABLE_CONTENT_POINTER_METADATA_PROBE=skipped'
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
