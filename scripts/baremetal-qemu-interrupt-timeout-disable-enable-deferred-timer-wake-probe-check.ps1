param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-interrupt-timeout-disable-enable-probe-check.ps1"
$taskStateReady = 1
$waitConditionNone = 0
$wakeReasonTimer = 1

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
if ($probeText -match 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_ENABLE_PROBE=skipped') {
    Write-Output 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_ENABLE_DEFERRED_TIMER_WAKE_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying interrupt-timeout disable-enable probe failed with exit code $probeExitCode"
}

$task0Id = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_ENABLE_PROBE_TASK0_ID'
$task0State = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_ENABLE_PROBE_TASK0_STATE'
$waitKind0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_ENABLE_PROBE_WAIT_KIND0'
$waitTimeout0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_ENABLE_PROBE_WAIT_TIMEOUT0'
$wake0TaskId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_ENABLE_PROBE_WAKE0_TASK_ID'
$wake0TimerId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_ENABLE_PROBE_WAKE0_TIMER_ID'
$wake0Reason = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_ENABLE_PROBE_WAKE0_REASON'
$wake0Vector = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_ENABLE_PROBE_WAKE0_VECTOR'
$wake0Tick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_ENABLE_PROBE_WAKE0_TICK'
$preWakeTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_ENABLE_PROBE_PRE_WAKE_TICK'

if ($null -in @($task0Id, $task0State, $waitKind0, $waitTimeout0, $wake0TaskId, $wake0TimerId, $wake0Reason, $wake0Vector, $wake0Tick, $preWakeTick)) {
    throw 'Missing expected deferred timer wake fields in probe output.'
}
if ($task0State -ne $taskStateReady) {
    throw "Expected waiter to become ready after re-enable wake. got state=$task0State"
}
if ($waitKind0 -ne $waitConditionNone) {
    throw "Expected wait kind to clear to none after deferred wake. got $waitKind0"
}
if ($waitTimeout0 -ne 0) {
    throw "Expected timeout arm to clear after deferred wake. got $waitTimeout0"
}
if ($wake0TaskId -ne $task0Id) {
    throw "Expected deferred wake to target the original waiting task. task=$task0Id wakeTask=$wake0TaskId"
}
if ($wake0TimerId -ne 0) {
    throw "Expected timeout-backed interrupt wait wake to surface with timer_id=0. got $wake0TimerId"
}
if ($wake0Reason -ne $wakeReasonTimer) {
    throw "Expected deferred wake to remain timer-based. got reason=$wake0Reason"
}
if ($wake0Vector -ne 0) {
    throw "Expected deferred timer wake to keep vector=0. got $wake0Vector"
}
if ($wake0Tick -ne $preWakeTick) {
    throw "Expected deferred wake tick to line up with the paused-window wake boundary. preWakeTick=$preWakeTick wakeTick=$wake0Tick"
}

Write-Output 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_ENABLE_DEFERRED_TIMER_WAKE_PROBE=pass'
Write-Output "TASK0_ID=$task0Id"
Write-Output "WAKE0_TASK_ID=$wake0TaskId"
Write-Output "WAKE0_TIMER_ID=$wake0TimerId"
Write-Output "WAKE0_REASON=$wake0Reason"
Write-Output "WAKE0_VECTOR=$wake0Vector"
