param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-wake-queue-before-tick-probe-check.ps1"
$skipToken = 'BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_NOTFOUND_PROBE=skipped'

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $pattern = '(?m)^' + [regex]::Escape($Name) + '=(-?\d+)\r?$'
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$probeOutput = if ($SkipBuild) { & $probe -SkipBuild 2>&1 } else { & $probe 2>&1 }
$probeExitCode = $LASTEXITCODE
$probeText = ($probeOutput | Out-String)
$probeOutput | Write-Output
if ($probeText -match 'BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_PROBE=skipped') {
    Write-Output $skipToken
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying wake-queue before-tick probe failed with exit code $probeExitCode"
}

$ack = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_ACK'
$lastOpcode = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_LAST_OPCODE'
$lastResult = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_LAST_RESULT'
if ($null -in @($ack,$lastOpcode,$lastResult)) {
    throw 'Missing expected notfound fields in wake-queue before-tick probe output.'
}
if ($ack -ne 19) { throw "Expected ACK=19. got $ack" }
if ($lastOpcode -ne 61) { throw "Expected LAST_OPCODE=61. got $lastOpcode" }
if ($lastResult -ne -2) { throw "Expected LAST_RESULT=-2. got $lastResult" }
Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_NOTFOUND_PROBE=pass'
Write-Output "ACK=$ack"
Write-Output "LAST_OPCODE=$lastOpcode"
Write-Output "LAST_RESULT=$lastResult"

