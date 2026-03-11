param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-command-health-history-probe-check.ps1"

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
if ($probeText -match 'BAREMETAL_QEMU_COMMAND_HEALTH_HISTORY_PROBE=skipped') {
    Write-Output 'BAREMETAL_QEMU_COMMAND_HEALTH_HISTORY_COMMAND_PAYLOADS_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying command-health history probe failed with exit code $probeExitCode"
}

$firstSeq = Extract-IntValue -Text $probeText -Name 'COMMAND_HISTORY_FIRST_SEQ'
$firstArg0 = Extract-IntValue -Text $probeText -Name 'COMMAND_HISTORY_FIRST_ARG0'
$lastSeq = Extract-IntValue -Text $probeText -Name 'COMMAND_HISTORY_LAST_SEQ'
$lastArg0 = Extract-IntValue -Text $probeText -Name 'COMMAND_HISTORY_LAST_ARG0'

if ($null -in @($firstSeq, $firstArg0, $lastSeq, $lastArg0)) {
    throw 'Missing command-history payload fields.'
}
if ($firstSeq -ne 4) { throw "Expected COMMAND_HISTORY_FIRST_SEQ=4. got $firstSeq" }
if ($firstArg0 -ne 103) { throw "Expected COMMAND_HISTORY_FIRST_ARG0=103. got $firstArg0" }
if ($lastSeq -ne 35) { throw "Expected COMMAND_HISTORY_LAST_SEQ=35. got $lastSeq" }
if ($lastArg0 -ne 134) { throw "Expected COMMAND_HISTORY_LAST_ARG0=134. got $lastArg0" }

Write-Output 'BAREMETAL_QEMU_COMMAND_HEALTH_HISTORY_COMMAND_PAYLOADS_PROBE=pass'
Write-Output "COMMAND_HISTORY_FIRST_SEQ=$firstSeq"
Write-Output "COMMAND_HISTORY_FIRST_ARG0=$firstArg0"
Write-Output "COMMAND_HISTORY_LAST_SEQ=$lastSeq"
Write-Output "COMMAND_HISTORY_LAST_ARG0=$lastArg0"
