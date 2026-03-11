param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-periodic-timer-probe-check.ps1"

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
if ($probeText -match 'BAREMETAL_QEMU_PERIODIC_TIMER_PROBE=skipped') {
    Write-Output 'BAREMETAL_QEMU_PERIODIC_TIMER_BASELINE_PROBE_CHECK=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying periodic-timer probe failed with exit code $probeExitCode"
}

$taskCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_TIMER_PROBE_SCHED_TASK_COUNT'
$taskId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_TIMER_PROBE_TASK0_ID'
$taskPriority = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_TIMER_PROBE_TASK0_PRIORITY'
$taskBudget = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_TIMER_PROBE_TASK0_BUDGET'
$timerEnabled = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_TIMER_PROBE_TIMER_ENABLED'
$entryCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_TIMER_PROBE_TIMER_ENTRY_COUNT'
$timerQuantum = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_TIMER_PROBE_TIMER_QUANTUM'
$timerId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_TIMER_PROBE_TIMER0_ID'
$timerTaskId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_TIMER_PROBE_TIMER0_TASK_ID'
$timerFlags = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_TIMER_PROBE_TIMER0_FLAGS'
$periodTicks = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_TIMER_PROBE_TIMER0_PERIOD_TICKS'
if ($null -in @($taskCount, $taskId, $taskPriority, $taskBudget, $timerEnabled, $entryCount, $timerQuantum, $timerId, $timerTaskId, $timerFlags, $periodTicks)) { throw 'Missing periodic-timer baseline fields.' }
if ($taskCount -ne 1) { throw "Expected SCHED_TASK_COUNT=1. got $taskCount" }
if ($taskId -ne 1) { throw "Expected TASK0_ID=1. got $taskId" }
if ($taskPriority -ne 1) { throw "Expected TASK0_PRIORITY=1. got $taskPriority" }
if ($taskBudget -ne 8) { throw "Expected TASK0_BUDGET=8. got $taskBudget" }
if ($timerEnabled -ne 1) { throw "Expected TIMER_ENABLED=1. got $timerEnabled" }
if ($entryCount -ne 1) { throw "Expected TIMER_ENTRY_COUNT=1. got $entryCount" }
if ($timerQuantum -ne 2) { throw "Expected TIMER_QUANTUM=2. got $timerQuantum" }
if ($timerId -ne 1) { throw "Expected TIMER0_ID=1. got $timerId" }
if ($timerTaskId -ne $taskId) { throw "Expected TIMER0_TASK_ID=$taskId. got $timerTaskId" }
if ($timerFlags -ne 1) { throw "Expected TIMER0_FLAGS=1. got $timerFlags" }
if ($periodTicks -ne 2) { throw "Expected TIMER0_PERIOD_TICKS=2. got $periodTicks" }
Write-Output 'BAREMETAL_QEMU_PERIODIC_TIMER_BASELINE_PROBE=pass'
Write-Output "SCHED_TASK_COUNT=$taskCount"
Write-Output "TASK0_ID=$taskId"
Write-Output "TASK0_PRIORITY=$taskPriority"
Write-Output "TASK0_BUDGET=$taskBudget"
Write-Output "TIMER_ENABLED=$timerEnabled"
Write-Output "TIMER_ENTRY_COUNT=$entryCount"
Write-Output "TIMER_QUANTUM=$timerQuantum"
Write-Output "TIMER0_ID=$timerId"
Write-Output "TIMER0_TASK_ID=$timerTaskId"
Write-Output "TIMER0_FLAGS=$timerFlags"
Write-Output "TIMER0_PERIOD_TICKS=$periodTicks"
