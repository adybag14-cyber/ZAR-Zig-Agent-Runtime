param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 30,
    [int] $GdbPort = 0
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-mailbox-stale-seq-probe-check.ps1"

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
if ($probeText -match '(?m)^BAREMETAL_QEMU_MAILBOX_STALE_SEQ_PROBE=skipped\r?$') {
    Write-Output 'BAREMETAL_QEMU_MAILBOX_STALE_SEQ_FIRST_STATE_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying mailbox stale-seq probe failed with exit code $probeExitCode"
}

$expected = @{
    'FIRST_ACK' = 1
    'FIRST_LAST_OPCODE' = 6
    'FIRST_LAST_RESULT' = 0
    'FIRST_TICK_BATCH_HINT' = 4
}
foreach ($entry in $expected.GetEnumerator()) {
    $actual = Extract-IntValue -Text $probeText -Name $entry.Key
    if ($null -eq $actual) { throw "Missing output value for $($entry.Key)" }
    if ($actual -ne $entry.Value) { throw "Unexpected $($entry.Key): got $actual expected $($entry.Value)" }
}

Write-Output 'BAREMETAL_QEMU_MAILBOX_STALE_SEQ_FIRST_STATE_PROBE=pass'
Write-Output 'FIRST_ACK=1'
Write-Output 'FIRST_LAST_OPCODE=6'
Write-Output 'FIRST_TICK_BATCH_HINT=4'
