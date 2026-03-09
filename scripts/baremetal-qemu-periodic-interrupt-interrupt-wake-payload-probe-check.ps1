param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-periodic-interrupt-probe-check.ps1"
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
if ($probeText -match '(?m)^BAREMETAL_QEMU_PERIODIC_INTERRUPT_PROBE=skipped\r?$') {
    Write-Output 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_INTERRUPT_WAKE_PAYLOAD_PROBE=skipped'
    Write-Output 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_INTERRUPT_WAKE_PAYLOAD_PROBE_SOURCE=baremetal-qemu-periodic-interrupt-probe-check.ps1'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying periodic-interrupt probe failed with exit code $probeExitCode"
}

$interruptDeadline = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_PROBE_INTERRUPT_DEADLINE'
$interruptWakeTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_PROBE_INTERRUPT_WAKE_TICK'
$wake0Tick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_PROBE_WAKE0_TICK'
$wake1Seq = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_PROBE_WAKE1_SEQ'
$wake1TaskId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_PROBE_WAKE1_TASK_ID'
$wake1TimerId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_PROBE_WAKE1_TIMER_ID'
$wake1Reason = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_PROBE_WAKE1_REASON'
$wake1Vector = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_PROBE_WAKE1_VECTOR'
$wake1Tick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_PROBE_WAKE1_TICK'

if ($null -in @($interruptDeadline, $interruptWakeTick, $wake0Tick, $wake1Seq, $wake1TaskId, $wake1TimerId, $wake1Reason, $wake1Vector, $wake1Tick)) {
    throw 'Missing expected periodic-interrupt interrupt-wake fields in probe output.'
}
if ($interruptDeadline -le 0) { throw "Expected INTERRUPT_DEADLINE > 0, got $interruptDeadline" }
if ($interruptWakeTick -le 0) { throw "Expected INTERRUPT_WAKE_TICK > 0, got $interruptWakeTick" }
if ($wake1Seq -ne 2) { throw "Expected WAKE1_SEQ=2, got $wake1Seq" }
if ($wake1TaskId -ne 2) { throw "Expected WAKE1_TASK_ID=2, got $wake1TaskId" }
if ($wake1TimerId -ne 0) { throw "Expected WAKE1_TIMER_ID=0, got $wake1TimerId" }
if ($wake1Reason -ne $wakeReasonInterrupt) { throw "Expected WAKE1_REASON=2, got $wake1Reason" }
if ($wake1Vector -ne $interruptVector) { throw "Expected WAKE1_VECTOR=31, got $wake1Vector" }
if ($wake1Tick -le $wake0Tick) { throw "Expected WAKE1_TICK > WAKE0_TICK. got wake0=$wake0Tick wake1=$wake1Tick" }
if ($interruptWakeTick -lt $wake1Tick) { throw "Expected INTERRUPT_WAKE_TICK >= WAKE1_TICK. wake1=$wake1Tick interruptWake=$interruptWakeTick" }
if ($wake1Tick -ge $interruptDeadline) { throw "Expected WAKE1_TICK < INTERRUPT_DEADLINE. wake1=$wake1Tick deadline=$interruptDeadline" }

Write-Output 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_INTERRUPT_WAKE_PAYLOAD_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_INTERRUPT_WAKE_PAYLOAD_PROBE_SOURCE=baremetal-qemu-periodic-interrupt-probe-check.ps1'
Write-Output "INTERRUPT_DEADLINE=$interruptDeadline"
Write-Output "INTERRUPT_WAKE_TICK=$interruptWakeTick"
Write-Output "WAKE0_TICK=$wake0Tick"
Write-Output "WAKE1_SEQ=$wake1Seq"
Write-Output "WAKE1_TASK_ID=$wake1TaskId"
Write-Output "WAKE1_TIMER_ID=$wake1TimerId"
Write-Output "WAKE1_REASON=$wake1Reason"
Write-Output "WAKE1_VECTOR=$wake1Vector"
Write-Output "WAKE1_TICK=$wake1Tick"
