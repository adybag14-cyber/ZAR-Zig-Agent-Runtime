param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-timer-wake-probe-check.ps1"

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
if ($probeText -match 'BAREMETAL_QEMU_TIMER_WAKE_PROBE=skipped') {
    Write-Output 'BAREMETAL_QEMU_TIMER_WAKE_TASK_STATE_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying timer-wake probe failed with exit code $probeExitCode"
}

$task0State = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_WAKE_PROBE_TASK0_STATE'
$task0RunCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_WAKE_PROBE_TASK0_RUN_COUNT'
$task0Budget = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_WAKE_PROBE_TASK0_BUDGET'
$task0BudgetRemaining = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_WAKE_PROBE_TASK0_BUDGET_REMAINING'

if ($null -in @($task0State, $task0RunCount, $task0Budget, $task0BudgetRemaining)) {
    throw 'Missing expected task-state fields in timer-wake probe output.'
}
if ($task0State -ne 1) { throw "Expected TASK0_STATE=1. got $task0State" }
if ($task0RunCount -ne 0) { throw "Expected TASK0_RUN_COUNT=0. got $task0RunCount" }
if ($task0Budget -ne 9) { throw "Expected TASK0_BUDGET=9. got $task0Budget" }
if ($task0BudgetRemaining -ne $task0Budget) { throw "Expected TASK0_BUDGET_REMAINING to equal TASK0_BUDGET. got $task0BudgetRemaining vs $task0Budget" }

Write-Output 'BAREMETAL_QEMU_TIMER_WAKE_TASK_STATE_PROBE=pass'
Write-Output "TASK0_STATE=$task0State"
Write-Output "TASK0_RUN_COUNT=$task0RunCount"
Write-Output "TASK0_BUDGET=$task0Budget"
Write-Output "TASK0_BUDGET_REMAINING=$task0BudgetRemaining"
