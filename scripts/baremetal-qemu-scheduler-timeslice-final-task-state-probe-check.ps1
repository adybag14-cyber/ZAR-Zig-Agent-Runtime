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
    Write-Output 'BAREMETAL_QEMU_SCHEDULER_TIMESLICE_FINAL_TASK_STATE_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying scheduler-timeslice-update probe failed with exit code $probeExitCode"
}

$enabled = Extract-IntValue -Text $probeText -Name 'ENABLED'
$taskCount = Extract-IntValue -Text $probeText -Name 'TASK_COUNT'
$runningSlot = Extract-IntValue -Text $probeText -Name 'RUNNING_SLOT'
$dispatchCount = Extract-IntValue -Text $probeText -Name 'DISPATCH_COUNT'
$taskId = Extract-IntValue -Text $probeText -Name 'TASK0_ID'
$taskState = Extract-IntValue -Text $probeText -Name 'TASK0_STATE'
$taskPriority = Extract-IntValue -Text $probeText -Name 'TASK0_PRIORITY'
$taskBudget = Extract-IntValue -Text $probeText -Name 'TASK0_BUDGET'
$taskRunCount = Extract-IntValue -Text $probeText -Name 'TASK0_RUN_COUNT'
$taskBudgetRemaining = Extract-IntValue -Text $probeText -Name 'TASK0_BUDGET_REMAINING'

if ($null -in @($enabled, $taskCount, $runningSlot, $dispatchCount, $taskId, $taskState, $taskPriority, $taskBudget, $taskRunCount, $taskBudgetRemaining)) {
    throw 'Missing expected final task-state fields in scheduler-timeslice-update probe output.'
}
if ($enabled -ne 1) { throw "Expected ENABLED=1. got $enabled" }
if ($taskCount -ne 1) { throw "Expected TASK_COUNT=1. got $taskCount" }
if ($runningSlot -ne 0) { throw "Expected RUNNING_SLOT=0. got $runningSlot" }
if ($dispatchCount -lt 4) { throw "Expected DISPATCH_COUNT>=4. got $dispatchCount" }
if ($taskId -ne 1) { throw "Expected TASK0_ID=1. got $taskId" }
if ($taskState -ne 1) { throw "Expected TASK0_STATE=1. got $taskState" }
if ($taskPriority -ne 2) { throw "Expected TASK0_PRIORITY=2. got $taskPriority" }
if ($taskBudget -ne 10) { throw "Expected TASK0_BUDGET=10. got $taskBudget" }
if ($taskRunCount -ne 4) { throw "Expected TASK0_RUN_COUNT=4. got $taskRunCount" }
if ($taskBudgetRemaining -ne 1) { throw "Expected TASK0_BUDGET_REMAINING=1. got $taskBudgetRemaining" }

Write-Output 'BAREMETAL_QEMU_SCHEDULER_TIMESLICE_FINAL_TASK_STATE_PROBE=pass'
Write-Output "ENABLED=$enabled"
Write-Output "TASK_COUNT=$taskCount"
Write-Output "RUNNING_SLOT=$runningSlot"
Write-Output "DISPATCH_COUNT=$dispatchCount"
Write-Output "TASK0_ID=$taskId"
Write-Output "TASK0_STATE=$taskState"
Write-Output "TASK0_PRIORITY=$taskPriority"
Write-Output "TASK0_BUDGET=$taskBudget"
Write-Output "TASK0_RUN_COUNT=$taskRunCount"
Write-Output "TASK0_BUDGET_REMAINING=$taskBudgetRemaining"