param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-interrupt-timeout-probe-check.ps1"
$waitConditionNone = 0
$taskStateReady = 1
$wakeReasonInterrupt = 2
$interruptVector = 31

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $match = [regex]::Match($Text, '(?m)^' + [regex]::Escape($Name) + '=(-?\d+)\r?$')
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$probeOutput = if ($SkipBuild) { & $probe -SkipBuild 2>&1 } else { & $probe 2>&1 }
$probeExitCode = $LASTEXITCODE
$probeText = ($probeOutput | Out-String)
$probeOutput | Write-Output
if ($probeText -match '(?m)^BAREMETAL_QEMU_INTERRUPT_TIMEOUT_PROBE=skipped\r?$') {
    Write-Output 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_INTERRUPT_WAKE_PAYLOAD_PROBE=skipped'
    Write-Output 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_INTERRUPT_WAKE_PAYLOAD_PROBE_SOURCE=baremetal-qemu-interrupt-timeout-probe-check.ps1'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying interrupt-timeout probe failed with exit code $probeExitCode"
}

$task0Id = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_PROBE_TASK0_ID'
$task0State = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_PROBE_TASK0_STATE'
$waitKind0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_PROBE_WAIT_KIND0'
$waitVector0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_PROBE_WAIT_VECTOR0'
$waitTimeout0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_PROBE_WAIT_TIMEOUT0'
$wakeQueueCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_PROBE_WAKE_QUEUE_COUNT'
$wake0TaskId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_PROBE_WAKE0_TASK_ID'
$wake0TimerId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_PROBE_WAKE0_TIMER_ID'
$wake0Reason = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_PROBE_WAKE0_REASON'
$wake0Vector = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_PROBE_WAKE0_VECTOR'
$wake0Tick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_PROBE_WAKE0_TICK'
$wake0Seq = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_PROBE_WAKE0_SEQ'
$beforeInterruptTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_PROBE_BEFORE_INTERRUPT_TICK'

if ($null -in @($task0Id, $task0State, $waitKind0, $waitVector0, $waitTimeout0, $wakeQueueCount, $wake0TaskId, $wake0TimerId, $wake0Reason, $wake0Vector, $wake0Tick, $wake0Seq, $beforeInterruptTick)) {
    throw 'Missing expected interrupt-timeout interrupt-wake-payload fields in probe output.'
}
if ($task0Id -le 0) { throw "Expected TASK0_ID > 0, got $task0Id" }
if ($task0State -ne $taskStateReady) { throw "Expected TASK0_STATE=1, got $task0State" }
if ($waitKind0 -ne $waitConditionNone) { throw "Expected WAIT_KIND0=0, got $waitKind0" }
if ($waitVector0 -ne 0) { throw "Expected WAIT_VECTOR0=0, got $waitVector0" }
if ($waitTimeout0 -ne 0) { throw "Expected WAIT_TIMEOUT0=0, got $waitTimeout0" }
if ($wakeQueueCount -ne 1) { throw "Expected WAKE_QUEUE_COUNT=1, got $wakeQueueCount" }
if ($wake0TaskId -ne $task0Id) { throw "Expected WAKE0_TASK_ID to match TASK0_ID. wake=$wake0TaskId task=$task0Id" }
if ($wake0TimerId -ne 0) { throw "Expected WAKE0_TIMER_ID=0, got $wake0TimerId" }
if ($wake0Reason -ne $wakeReasonInterrupt) { throw "Expected WAKE0_REASON=2, got $wake0Reason" }
if ($wake0Vector -ne $interruptVector) { throw "Expected WAKE0_VECTOR=31, got $wake0Vector" }
if ($wake0Seq -ne 1) { throw "Expected WAKE0_SEQ=1, got $wake0Seq" }
if ($wake0Tick -lt $beforeInterruptTick) { throw "Expected WAKE0_TICK >= BEFORE_INTERRUPT_TICK. wake=$wake0Tick before=$beforeInterruptTick" }

Write-Output 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_INTERRUPT_WAKE_PAYLOAD_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_INTERRUPT_WAKE_PAYLOAD_PROBE_SOURCE=baremetal-qemu-interrupt-timeout-probe-check.ps1'
Write-Output "TASK0_ID=$task0Id"
Write-Output "TASK0_STATE=$task0State"
Write-Output "WAIT_KIND0=$waitKind0"
Write-Output "WAIT_VECTOR0=$waitVector0"
Write-Output "WAIT_TIMEOUT0=$waitTimeout0"
Write-Output "WAKE_QUEUE_COUNT=$wakeQueueCount"
Write-Output "WAKE0_TASK_ID=$wake0TaskId"
Write-Output "WAKE0_TIMER_ID=$wake0TimerId"
Write-Output "WAKE0_REASON=$wake0Reason"
Write-Output "WAKE0_VECTOR=$wake0Vector"
Write-Output "WAKE0_TICK=$wake0Tick"
Write-Output "WAKE0_SEQ=$wake0Seq"
Write-Output "BEFORE_INTERRUPT_TICK=$beforeInterruptTick"
