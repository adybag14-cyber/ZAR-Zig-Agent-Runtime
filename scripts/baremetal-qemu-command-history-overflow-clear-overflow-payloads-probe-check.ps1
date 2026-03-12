param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 90
)

$ErrorActionPreference = 'Stop'
$probe = Join-Path $PSScriptRoot 'baremetal-qemu-command-history-overflow-clear-probe-check.ps1'
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $match = [regex]::Match($Text, '(?m)^' + [regex]::Escape($Name) + '=(-?\d+)\r?$')
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$invoke = @{ TimeoutSeconds = $TimeoutSeconds }
if ($SkipBuild) { $invoke.SkipBuild = $true }

$output = & $probe @invoke 2>&1
$exitCode = $LASTEXITCODE
$outputText = ($output | Out-String)
if ($outputText -match '(?m)^BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_PROBE=skipped\r?$') {
    if ($outputText) { Write-Output $outputText.TrimEnd() }
    Write-Output 'BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_OVERFLOW_PAYLOADS_PROBE=skipped'
    Write-Output 'BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_OVERFLOW_PAYLOADS_PROBE_SOURCE=baremetal-qemu-command-history-overflow-clear-probe-check.ps1'
    exit 0
}
if ($exitCode -ne 0) {
    if ($outputText) { Write-Output $outputText.TrimEnd() }
    throw "Command-history overflow/clear prerequisite probe failed with exit code $exitCode"
}

$firstArg0 = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_PROBE_FIRST_ARG0'
$lastArg0 = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_PROBE_LAST_ARG0'
if ($firstArg0 -ne 103 -or $lastArg0 -ne 134) {
    throw "Unexpected overflow payloads. firstArg0=$firstArg0 lastArg0=$lastArg0"
}

Write-Output 'BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_OVERFLOW_PAYLOADS_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_OVERFLOW_PAYLOADS_PROBE_SOURCE=baremetal-qemu-command-history-overflow-clear-probe-check.ps1'
Write-Output "FIRST_ARG0=$firstArg0"
Write-Output "LAST_ARG0=$lastArg0"
