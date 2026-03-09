param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 40,
    [int] $GdbPort = 1438
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-timer-disable-interrupt-probe-check.ps1"

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $match = [regex]::Match($Text, '(?m)^' + [regex]::Escape($Name) + '=(-?\d+)\r?$')
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$invoke = @{ TimeoutSeconds = $TimeoutSeconds; GdbPort = $GdbPort }
if ($SkipBuild) { $invoke.SkipBuild = $true }

$probeOutput = & $probe @invoke 2>&1
$probeExitCode = $LASTEXITCODE
$probeText = ($probeOutput | Out-String)
$probeOutput | Write-Output
if ($probeText -match '(?m)^BAREMETAL_QEMU_TIMER_DISABLE_INTERRUPT_PROBE=skipped\r?$') {
    Write-Output 'BAREMETAL_QEMU_TIMER_DISABLE_INTERRUPT_IMMEDIATE_WAKE_PROBE=skipped'
    Write-Output 'BAREMETAL_QEMU_TIMER_DISABLE_INTERRUPT_IMMEDIATE_WAKE_PROBE_SOURCE=baremetal-qemu-timer-disable-interrupt-probe-check.ps1'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying timer-disable interrupt probe failed with exit code $probeExitCode"
}

$interruptTaskId = Extract-IntValue -Text $probeText -Name 'INTERRUPT_TASK_ID'
$afterInterruptTick = Extract-IntValue -Text $probeText -Name 'AFTER_INTERRUPT_TICK'
$afterInterruptWakeQueueCount = Extract-IntValue -Text $probeText -Name 'AFTER_INTERRUPT_WAKE_QUEUE_COUNT'
$afterInterruptInterruptTaskState = Extract-IntValue -Text $probeText -Name 'AFTER_INTERRUPT_INTERRUPT_TASK_STATE'
$afterInterruptTimerTaskState = Extract-IntValue -Text $probeText -Name 'AFTER_INTERRUPT_TIMER_TASK_STATE'
$wake0TaskId = Extract-IntValue -Text $probeText -Name 'WAKE0_TASK_ID'
$wake0TimerId = Extract-IntValue -Text $probeText -Name 'WAKE0_TIMER_ID'
$wake0Reason = Extract-IntValue -Text $probeText -Name 'WAKE0_REASON'
$wake0Vector = Extract-IntValue -Text $probeText -Name 'WAKE0_VECTOR'
$wake0Tick = Extract-IntValue -Text $probeText -Name 'WAKE0_TICK'
$wake0InterruptCount = Extract-IntValue -Text $probeText -Name 'WAKE0_INTERRUPT_COUNT'

if ($null -in @($interruptTaskId, $afterInterruptTick, $afterInterruptWakeQueueCount, $afterInterruptInterruptTaskState, $afterInterruptTimerTaskState, $wake0TaskId, $wake0TimerId, $wake0Reason, $wake0Vector, $wake0Tick, $wake0InterruptCount)) {
    throw 'Missing expected timer-disable immediate-wake fields in probe output.'
}
if ($interruptTaskId -le 0) { throw "Expected INTERRUPT_TASK_ID > 0, got $interruptTaskId" }
if ($afterInterruptTick -le 0) { throw "Expected AFTER_INTERRUPT_TICK > 0, got $afterInterruptTick" }
if ($afterInterruptWakeQueueCount -ne 1) { throw "Expected AFTER_INTERRUPT_WAKE_QUEUE_COUNT=1, got $afterInterruptWakeQueueCount" }
if ($afterInterruptInterruptTaskState -ne 1) { throw "Expected AFTER_INTERRUPT_INTERRUPT_TASK_STATE=1, got $afterInterruptInterruptTaskState" }
if ($afterInterruptTimerTaskState -ne 6) { throw "Expected AFTER_INTERRUPT_TIMER_TASK_STATE=6, got $afterInterruptTimerTaskState" }
if ($wake0TaskId -ne $interruptTaskId) { throw "Expected WAKE0_TASK_ID=$interruptTaskId, got $wake0TaskId" }
if ($wake0TimerId -ne 0) { throw "Expected WAKE0_TIMER_ID=0, got $wake0TimerId" }
if ($wake0Reason -ne 2) { throw "Expected WAKE0_REASON=2, got $wake0Reason" }
if ($wake0Vector -ne 200) { throw "Expected WAKE0_VECTOR=200, got $wake0Vector" }
if ($wake0Tick -gt $afterInterruptTick) { throw "Expected WAKE0_TICK <= AFTER_INTERRUPT_TICK. got WAKE0_TICK=$wake0Tick AFTER_INTERRUPT_TICK=$afterInterruptTick" }
if ($wake0InterruptCount -lt 1) { throw "Expected WAKE0_INTERRUPT_COUNT >= 1, got $wake0InterruptCount" }

Write-Output 'BAREMETAL_QEMU_TIMER_DISABLE_INTERRUPT_IMMEDIATE_WAKE_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_TIMER_DISABLE_INTERRUPT_IMMEDIATE_WAKE_PROBE_SOURCE=baremetal-qemu-timer-disable-interrupt-probe-check.ps1'
Write-Output "INTERRUPT_TASK_ID=$interruptTaskId"
Write-Output "AFTER_INTERRUPT_TICK=$afterInterruptTick"
Write-Output "AFTER_INTERRUPT_WAKE_QUEUE_COUNT=$afterInterruptWakeQueueCount"
Write-Output "WAKE0_TASK_ID=$wake0TaskId"
Write-Output "WAKE0_TIMER_ID=$wake0TimerId"
Write-Output "WAKE0_REASON=$wake0Reason"
Write-Output "WAKE0_VECTOR=$wake0Vector"
