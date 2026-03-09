param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-scheduler-timeslice-update-probe-check.ps1"

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
    Write-Output 'BAREMETAL_QEMU_SCHEDULER_TIMESLICE_UPDATE_2_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying scheduler-timeslice-update probe failed with exit code $probeExitCode"
}

$midTimeslice = Extract-IntValue -Text $probeText -Name 'MID_TIMESLICE_2'
$midRunCount = Extract-IntValue -Text $probeText -Name 'MID_RUN_COUNT_2'
$midBudgetRemaining = Extract-IntValue -Text $probeText -Name 'MID_BUDGET_REMAINING_2'

if ($null -in @($midTimeslice, $midRunCount, $midBudgetRemaining)) {
    throw 'Missing expected timeslice=2 fields in scheduler-timeslice-update probe output.'
}
if ($midTimeslice -ne 2) { throw "Expected MID_TIMESLICE_2=2. got $midTimeslice" }
if ($midRunCount -ne 3) { throw "Expected MID_RUN_COUNT_2=3. got $midRunCount" }
if ($midBudgetRemaining -ne 3) { throw "Expected MID_BUDGET_REMAINING_2=3. got $midBudgetRemaining" }

Write-Output 'BAREMETAL_QEMU_SCHEDULER_TIMESLICE_UPDATE_2_PROBE=pass'
Write-Output "MID_TIMESLICE_2=$midTimeslice"
Write-Output "MID_RUN_COUNT_2=$midRunCount"
Write-Output "MID_BUDGET_REMAINING_2=$midBudgetRemaining"