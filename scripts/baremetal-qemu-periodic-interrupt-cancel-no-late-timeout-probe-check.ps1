param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-periodic-interrupt-probe-check.ps1"
$timerCancelTaskOpcode = 52
$waitConditionNone = 0
$postDeadlineSlackTicks = 2

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
    Write-Output 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_CANCEL_NO_LATE_TIMEOUT_PROBE=skipped'
    Write-Output 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_CANCEL_NO_LATE_TIMEOUT_PROBE_SOURCE=baremetal-qemu-periodic-interrupt-probe-check.ps1'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying periodic-interrupt probe failed with exit code $probeExitCode"
}

$lastOpcode = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_PROBE_LAST_OPCODE'
$lastResult = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_PROBE_LAST_RESULT'
$timerEntryCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_PROBE_TIMER_ENTRY_COUNT'
$timerDispatchCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_PROBE_TIMER_DISPATCH_COUNT'
$wakeQueueCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_PROBE_WAKE_QUEUE_COUNT'
$waitKind1 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_PROBE_WAIT_KIND1'
$waitVector1 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_PROBE_WAIT_VECTOR1'
$waitTimeout1 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_PROBE_WAIT_TIMEOUT1'
$ticks = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_PROBE_TICKS'
$interruptDeadline = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_PROBE_INTERRUPT_DEADLINE'

if ($null -in @($lastOpcode, $lastResult, $timerEntryCount, $timerDispatchCount, $wakeQueueCount, $waitKind1, $waitVector1, $waitTimeout1, $ticks, $interruptDeadline)) {
    throw 'Missing expected periodic-interrupt cancel/no-late-timeout fields in probe output.'
}
if ($lastOpcode -ne $timerCancelTaskOpcode) { throw "Expected LAST_OPCODE=52, got $lastOpcode" }
if ($lastResult -ne 0) { throw "Expected LAST_RESULT=0, got $lastResult" }
if ($timerEntryCount -ne 0) { throw "Expected TIMER_ENTRY_COUNT=0, got $timerEntryCount" }
if ($timerDispatchCount -ne 2) { throw "Expected TIMER_DISPATCH_COUNT=2, got $timerDispatchCount" }
if ($wakeQueueCount -ne 3) { throw "Expected WAKE_QUEUE_COUNT=3, got $wakeQueueCount" }
if ($waitKind1 -ne $waitConditionNone) { throw "Expected WAIT_KIND1=0, got $waitKind1" }
if ($waitVector1 -ne 0) { throw "Expected WAIT_VECTOR1=0, got $waitVector1" }
if ($waitTimeout1 -ne 0) { throw "Expected WAIT_TIMEOUT1=0, got $waitTimeout1" }
if ($ticks -lt ($interruptDeadline + $postDeadlineSlackTicks)) {
    throw "Expected TICKS >= INTERRUPT_DEADLINE + $postDeadlineSlackTicks. ticks=$ticks deadline=$interruptDeadline"
}

Write-Output 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_CANCEL_NO_LATE_TIMEOUT_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_CANCEL_NO_LATE_TIMEOUT_PROBE_SOURCE=baremetal-qemu-periodic-interrupt-probe-check.ps1'
Write-Output "LAST_OPCODE=$lastOpcode"
Write-Output "LAST_RESULT=$lastResult"
Write-Output "TIMER_ENTRY_COUNT=$timerEntryCount"
Write-Output "TIMER_DISPATCH_COUNT=$timerDispatchCount"
Write-Output "WAKE_QUEUE_COUNT=$wakeQueueCount"
Write-Output "WAIT_KIND1=$waitKind1"
Write-Output "WAIT_VECTOR1=$waitVector1"
Write-Output "WAIT_TIMEOUT1=$waitTimeout1"
Write-Output "TICKS=$ticks"
Write-Output "INTERRUPT_DEADLINE=$interruptDeadline"
