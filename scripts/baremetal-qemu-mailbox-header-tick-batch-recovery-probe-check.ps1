param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 30,
    [int] $GdbPort = 0
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-mailbox-header-validation-probe-check.ps1"

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $pattern = '(?m)^' + [regex]::Escape($Name) + '=(-?\d+)\r?$'
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$invoke = @{ TimeoutSeconds = $TimeoutSeconds; GdbPort = $GdbPort }
if ($SkipBuild) { $invoke.SkipBuild = $true }

$probeOutput = & $probe @invoke 2>&1
$probeExitCode = $LASTEXITCODE
$probeText = ($probeOutput | Out-String)
$probeOutput | Write-Output
if ($probeText -match '(?m)^BAREMETAL_QEMU_MAILBOX_HEADER_VALIDATION_PROBE=skipped\r?$') {
    Write-Output 'BAREMETAL_QEMU_MAILBOX_HEADER_TICK_BATCH_RECOVERY_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying mailbox header validation probe failed with exit code $probeExitCode"
}

$expected = @{
    'INVALID_MAGIC_TICK_BATCH_HINT' = 1
    'INVALID_API_VERSION_TICK_BATCH_HINT' = 1
    'TICK_BATCH_HINT' = 5
    'LAST_RESULT' = 0
}

foreach ($entry in $expected.GetEnumerator()) {
    $actual = Extract-IntValue -Text $probeText -Name $entry.Key
    if ($null -eq $actual) { throw "Missing output value for $($entry.Key)" }
    if ($actual -ne $entry.Value) { throw "Unexpected $($entry.Key): got $actual expected $($entry.Value)" }
}

$ticks = Extract-IntValue -Text $probeText -Name 'TICKS'
if ($null -eq $ticks) { throw 'Missing output value for TICKS' }
if ($ticks -le 0) { throw "Unexpected TICKS: got $ticks expected > 0" }

Write-Output 'BAREMETAL_QEMU_MAILBOX_HEADER_TICK_BATCH_RECOVERY_PROBE=pass'
Write-Output 'INVALID_MAGIC_TICK_BATCH_HINT=1'
Write-Output 'INVALID_API_VERSION_TICK_BATCH_HINT=1'
Write-Output 'TICK_BATCH_HINT=5'
Write-Output 'LAST_RESULT=0'
Write-Output "TICKS=$ticks"
