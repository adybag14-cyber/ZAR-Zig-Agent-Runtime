param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-timer-pressure-probe-check.ps1"
$skipToken = 'BAREMETAL_QEMU_TIMER_PRESSURE_QUIET_TELEMETRY_PROBE=skipped'

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
if ($probeText -match 'BAREMETAL_QEMU_TIMER_PRESSURE_PROBE=skipped') {
    Write-Output $skipToken
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying timer-pressure probe failed with exit code $probeExitCode"
}

$ack = Extract-IntValue -Text $probeText -Name 'ACK'
$lastOpcode = Extract-IntValue -Text $probeText -Name 'LAST_OPCODE'
$lastResult = Extract-IntValue -Text $probeText -Name 'LAST_RESULT'
$wakeCount = Extract-IntValue -Text $probeText -Name 'WAKE_COUNT'
$dispatchCount = Extract-IntValue -Text $probeText -Name 'DISPATCH_COUNT'
if ($null -in @($ack,$lastOpcode,$lastResult,$wakeCount,$dispatchCount)) {
    throw 'Missing timer-pressure quiet-telemetry fields.'
}
if ($ack -ne 38) { throw "Expected ACK=38. got $ack" }
if ($lastOpcode -ne 42) { throw "Expected LAST_OPCODE=42. got $lastOpcode" }
if ($lastResult -ne 0) { throw "Expected LAST_RESULT=0. got $lastResult" }
if ($wakeCount -ne 0) { throw "Expected WAKE_COUNT=0. got $wakeCount" }
if ($dispatchCount -ne 0) { throw "Expected DISPATCH_COUNT=0. got $dispatchCount" }

Write-Output 'BAREMETAL_QEMU_TIMER_PRESSURE_QUIET_TELEMETRY_PROBE=pass'
Write-Output "ACK=$ack"
Write-Output "LAST_OPCODE=$lastOpcode"
Write-Output "LAST_RESULT=$lastResult"
Write-Output "WAKE_COUNT=$wakeCount"
Write-Output "DISPATCH_COUNT=$dispatchCount"
