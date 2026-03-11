param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 30,
    [int] $GdbPort = 0
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-mode-boot-phase-setter-probe-check.ps1"

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $pattern = '(?m)^' + [regex]::Escape($Name) + '=(-?\d+)\r?$'
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$invoke = @{ TimeoutSeconds = $TimeoutSeconds }
if ($GdbPort -gt 0) { $invoke.GdbPort = $GdbPort }
if ($SkipBuild) { $invoke.SkipBuild = $true }

$probeOutput = & $probe @invoke 2>&1
$probeExitCode = $LASTEXITCODE
$probeText = ($probeOutput | Out-String)
$probeOutput | Write-Output
if ($probeText -match '(?m)^BAREMETAL_QEMU_MODE_BOOT_PHASE_SETTER_PROBE=skipped\r?$') {
    Write-Output 'BAREMETAL_QEMU_MODE_BOOT_PHASE_SETTER_BASELINE_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying mode/boot-phase setter probe failed with exit code $probeExitCode"
}

$expected = @{
    'ACK' = 9
    'LAST_OPCODE' = 4
    'LAST_RESULT' = 0
    'STATUS_MODE' = 1
    'PANIC_COUNT' = 0
    'BOOT_PHASE' = 1
    'BOOT_PHASE_CHANGES' = 1
}

foreach ($entry in $expected.GetEnumerator()) {
    $actual = Extract-IntValue -Text $probeText -Name $entry.Key
    if ($null -eq $actual) { throw "Missing output value for $($entry.Key)" }
    if ($actual -ne $entry.Value) { throw "Unexpected $($entry.Key): got $actual expected $($entry.Value)" }
}

$ticks = Extract-IntValue -Text $probeText -Name 'TICKS'
if ($null -eq $ticks) { throw 'Missing output value for TICKS' }
if ($ticks -lt 9) { throw "Unexpected TICKS: got $ticks expected at least 9" }

Write-Output 'BAREMETAL_QEMU_MODE_BOOT_PHASE_SETTER_BASELINE_PROBE=pass'
Write-Output 'ACK=9'
Write-Output 'LAST_OPCODE=4'
Write-Output 'LAST_RESULT=0'
Write-Output 'STATUS_MODE=1'
Write-Output 'PANIC_COUNT=0'
Write-Output 'BOOT_PHASE=1'
Write-Output 'BOOT_PHASE_CHANGES=1'
Write-Output "TICKS=$ticks"
