param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-scheduler-saturation-probe-check.ps1"
$output = if ($SkipBuild) {
    & powershell -ExecutionPolicy Bypass -File $probe -SkipBuild | Out-String
} else {
    & powershell -ExecutionPolicy Bypass -File $probe | Out-String
}

function Get-Int([string] $name) {
    $match = [regex]::Match($output, '(?m)^' + [regex]::Escape($name) + '=(-?\d+)\r?$')
    if (-not $match.Success) { throw "Missing $name" }
    return [int64]::Parse($match.Groups[1].Value)
}

$lastTaskId = Get-Int "BAREMETAL_QEMU_SCHEDULER_SATURATION_LAST_TASK_ID"
$newTaskId = Get-Int "BAREMETAL_QEMU_SCHEDULER_SATURATION_REUSED_SLOT_NEW_ID"
$reusedPriority = Get-Int "BAREMETAL_QEMU_SCHEDULER_SATURATION_REUSED_PRIORITY"
$reusedBudget = Get-Int "BAREMETAL_QEMU_SCHEDULER_SATURATION_REUSED_BUDGET_TICKS"

if ($newTaskId -le $lastTaskId) { throw "Expected REUSED_SLOT_NEW_ID > LAST_TASK_ID, got NEW=$newTaskId LAST=$lastTaskId" }
if ($reusedPriority -ne 99) { throw "Expected REUSED_PRIORITY=99, got $reusedPriority" }
if ($reusedBudget -ne 7) { throw "Expected REUSED_BUDGET_TICKS=7, got $reusedBudget" }

Write-Output "BAREMETAL_QEMU_SCHEDULER_SATURATION_REUSE_STATE_PROBE=pass"
Write-Output "LAST_TASK_ID=$lastTaskId"
Write-Output "REUSED_SLOT_NEW_ID=$newTaskId"
Write-Output "REUSED_PRIORITY=$reusedPriority"
Write-Output "REUSED_BUDGET_TICKS=$reusedBudget"
