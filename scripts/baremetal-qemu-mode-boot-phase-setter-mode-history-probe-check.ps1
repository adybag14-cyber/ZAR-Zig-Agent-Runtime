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
    Write-Output 'BAREMETAL_QEMU_MODE_BOOT_PHASE_SETTER_MODE_HISTORY_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying mode/boot-phase setter probe failed with exit code $probeExitCode"
}

$expected = @{
    'MODE_HISTORY_LEN' = 2
    'MODE0_SEQ' = 1
    'MODE0_PREV' = 1
    'MODE0_NEW' = 255
    'MODE0_REASON' = 1
    'MODE1_SEQ' = 2
    'MODE1_PREV' = 255
    'MODE1_NEW' = 1
    'MODE1_REASON' = 1
}

foreach ($entry in $expected.GetEnumerator()) {
    $actual = Extract-IntValue -Text $probeText -Name $entry.Key
    if ($null -eq $actual) { throw "Missing output value for $($entry.Key)" }
    if ($actual -ne $entry.Value) { throw "Unexpected $($entry.Key): got $actual expected $($entry.Value)" }
}

Write-Output 'BAREMETAL_QEMU_MODE_BOOT_PHASE_SETTER_MODE_HISTORY_PROBE=pass'
Write-Output 'MODE_HISTORY_LEN=2'
Write-Output 'MODE0_SEQ=1'
Write-Output 'MODE0_PREV=1'
Write-Output 'MODE0_NEW=255'
Write-Output 'MODE0_REASON=1'
Write-Output 'MODE1_SEQ=2'
Write-Output 'MODE1_PREV=255'
Write-Output 'MODE1_NEW=1'
Write-Output 'MODE1_REASON=1'
