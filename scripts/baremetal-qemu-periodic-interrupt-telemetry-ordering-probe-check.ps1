param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-periodic-interrupt-probe-check.ps1"
$wakeReasonTimer = 1
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
    Write-Output 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_TELEMETRY_ORDERING_PROBE=skipped'
    Write-Output 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_TELEMETRY_ORDERING_PROBE_SOURCE=baremetal-qemu-periodic-interrupt-probe-check.ps1'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying periodic-interrupt probe failed with exit code $probeExitCode"
}

$interruptCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_PROBE_INTERRUPT_COUNT'
$lastInterruptVector = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_PROBE_LAST_INTERRUPT_VECTOR'
$timerLastInterruptCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_PROBE_TIMER_LAST_INTERRUPT_COUNT'
$timerLastWakeTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_PROBE_TIMER_LAST_WAKE_TICK'
$wake0Reason = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_PROBE_WAKE0_REASON'
$wake0Tick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_PROBE_WAKE0_TICK'
$wake1Reason = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_PROBE_WAKE1_REASON'
$wake1Tick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_PROBE_WAKE1_TICK'
$wake2Reason = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_PROBE_WAKE2_REASON'
$wake2Tick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_PROBE_WAKE2_TICK'

if ($null -in @($interruptCount, $lastInterruptVector, $timerLastInterruptCount, $timerLastWakeTick, $wake0Reason, $wake0Tick, $wake1Reason, $wake1Tick, $wake2Reason, $wake2Tick)) {
    throw 'Missing expected periodic-interrupt telemetry-ordering fields in probe output.'
}
if ($interruptCount -ne 1) { throw "Expected INTERRUPT_COUNT=1, got $interruptCount" }
if ($lastInterruptVector -ne $interruptVector) { throw "Expected LAST_INTERRUPT_VECTOR=31, got $lastInterruptVector" }
if ($timerLastInterruptCount -ne 1) { throw "Expected TIMER_LAST_INTERRUPT_COUNT=1, got $timerLastInterruptCount" }
if ($wake0Reason -ne $wakeReasonTimer) { throw "Expected WAKE0_REASON=1, got $wake0Reason" }
if ($wake1Reason -ne $wakeReasonInterrupt) { throw "Expected WAKE1_REASON=2, got $wake1Reason" }
if ($wake2Reason -ne $wakeReasonTimer) { throw "Expected WAKE2_REASON=1, got $wake2Reason" }
if ($wake0Tick -ge $wake1Tick -or $wake1Tick -ge $wake2Tick) {
    throw "Expected WAKE0_TICK < WAKE1_TICK < WAKE2_TICK. got wake0=$wake0Tick wake1=$wake1Tick wake2=$wake2Tick"
}
if ($timerLastWakeTick -ne $wake2Tick) { throw "Expected TIMER_LAST_WAKE_TICK=$wake2Tick, got $timerLastWakeTick" }

Write-Output 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_TELEMETRY_ORDERING_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_TELEMETRY_ORDERING_PROBE_SOURCE=baremetal-qemu-periodic-interrupt-probe-check.ps1'
Write-Output "INTERRUPT_COUNT=$interruptCount"
Write-Output "LAST_INTERRUPT_VECTOR=$lastInterruptVector"
Write-Output "TIMER_LAST_INTERRUPT_COUNT=$timerLastInterruptCount"
Write-Output "TIMER_LAST_WAKE_TICK=$timerLastWakeTick"
Write-Output "WAKE0_REASON=$wake0Reason"
Write-Output "WAKE0_TICK=$wake0Tick"
Write-Output "WAKE1_REASON=$wake1Reason"
Write-Output "WAKE1_TICK=$wake1Tick"
Write-Output "WAKE2_REASON=$wake2Reason"
Write-Output "WAKE2_TICK=$wake2Tick"
