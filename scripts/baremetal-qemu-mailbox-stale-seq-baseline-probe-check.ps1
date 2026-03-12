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
    Write-Output 'BAREMETAL_QEMU_MAILBOX_STALE_SEQ_BASELINE_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying mailbox stale-seq probe failed with exit code $probeExitCode"
}

$required = @('FIRST_ACK','FIRST_LAST_OPCODE','FIRST_LAST_RESULT','FIRST_TICK_BATCH_HINT','FIRST_MAILBOX_SEQ','STALE_ACK','STALE_LAST_OPCODE','STALE_LAST_RESULT','STALE_TICK_BATCH_HINT','STALE_MAILBOX_SEQ','ACK','LAST_OPCODE','LAST_RESULT','TICKS','TICK_BATCH_HINT','MAILBOX_SEQ')
foreach ($name in $required) {
    $actual = Extract-IntValue -Text $probeText -Name $name
    if ($null -eq $actual) { throw "Missing output value for $name" }
}

$ticks = Extract-IntValue -Text $probeText -Name 'TICKS'
if ($ticks -lt 2) { throw "Expected TICKS >= 2, got $ticks" }

Write-Output 'BAREMETAL_QEMU_MAILBOX_STALE_SEQ_BASELINE_PROBE=pass'
Write-Output "FIRST_ACK=$(Extract-IntValue -Text $probeText -Name 'FIRST_ACK')"
Write-Output "STALE_ACK=$(Extract-IntValue -Text $probeText -Name 'STALE_ACK')"
Write-Output "ACK=$(Extract-IntValue -Text $probeText -Name 'ACK')"
