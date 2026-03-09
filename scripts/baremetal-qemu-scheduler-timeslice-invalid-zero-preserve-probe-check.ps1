param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-scheduler-timeslice-update-probe-check.ps1"
$schedulerSetTimesliceOpcode = 29

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
if ($probeText -match 'BAREMETAL_QEMU_SCHEDULER_TIMESLICE_UPDATE_PROBE=skipped') {
    Write-Output 'BAREMETAL_QEMU_SCHEDULER_TIMESLICE_INVALID_ZERO_PRESERVE_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying scheduler-timeslice-update probe failed with exit code $probeExitCode"
}

$ack = Extract-IntValue -Text $probeText -Name 'ACK'
$lastOpcode = Extract-IntValue -Text $probeText -Name 'LAST_OPCODE'
$lastResult = Extract-IntValue -Text $probeText -Name 'LAST_RESULT'
$timeslice = Extract-IntValue -Text $probeText -Name 'TIMESLICE'

if ($null -in @($ack, $lastOpcode, $lastResult, $timeslice)) {
    throw 'Missing expected invalid-zero preservation fields in scheduler-timeslice-update probe output.'
}
if ($ack -ne 6) { throw "Expected ACK=6. got $ack" }
if ($lastOpcode -ne $schedulerSetTimesliceOpcode) { throw "Expected LAST_OPCODE=29. got $lastOpcode" }
if ($lastResult -ne -22) { throw "Expected LAST_RESULT=-22. got $lastResult" }
if ($timeslice -ne 2) { throw "Expected TIMESLICE=2 after invalid zero. got $timeslice" }

Write-Output 'BAREMETAL_QEMU_SCHEDULER_TIMESLICE_INVALID_ZERO_PRESERVE_PROBE=pass'
Write-Output "ACK=$ack"
Write-Output "LAST_OPCODE=$lastOpcode"
Write-Output "LAST_RESULT=$lastResult"
Write-Output "TIMESLICE=$timeslice"