param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-interrupt-timeout-disable-interrupt-probe-check.ps1"

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
if ($probeText -match 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_INTERRUPT_PROBE=skipped') {
    Write-Output 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_INTERRUPT_REENABLE_NO_STALE_TIMER_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying interrupt-timeout disable-interrupt probe failed with exit code $probeExitCode"
}

$finalTimerEnabled = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_INTERRUPT_PROBE_FINAL_TIMER_ENABLED'
$finalTimerDispatchCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_INTERRUPT_PROBE_FINAL_TIMER_DISPATCH_COUNT'
$finalWakeQueueCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_INTERRUPT_PROBE_FINAL_WAKE_QUEUE_COUNT'
$finalWake0Reason = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_INTERRUPT_PROBE_FINAL_WAKE0_REASON'
$finalWake0Vector = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_INTERRUPT_PROBE_FINAL_WAKE0_VECTOR'
if ($null -in @($finalTimerEnabled, $finalTimerDispatchCount, $finalWakeQueueCount, $finalWake0Reason, $finalWake0Vector)) {
    throw 'Missing final re-enable fields in probe output.'
}
if ($finalTimerEnabled -ne 1) { throw "Expected timers enabled after re-enable. got $finalTimerEnabled" }
if ($finalTimerDispatchCount -ne 0) { throw "Expected no stale timer dispatch after re-enable. got $finalTimerDispatchCount" }
if ($finalWakeQueueCount -ne 1) { throw "Expected exactly one retained wake after re-enable. got $finalWakeQueueCount" }
if ($finalWake0Reason -ne 2) { throw "Expected retained wake reason interrupt (2). got $finalWake0Reason" }
if ($finalWake0Vector -ne 31) { throw "Expected retained wake vector 31. got $finalWake0Vector" }

Write-Output 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_INTERRUPT_REENABLE_NO_STALE_TIMER_PROBE=pass'
Write-Output "FINAL_TIMER_ENABLED=$finalTimerEnabled"
Write-Output "FINAL_TIMER_DISPATCH_COUNT=$finalTimerDispatchCount"
Write-Output "FINAL_WAKE_QUEUE_COUNT=$finalWakeQueueCount"
Write-Output "FINAL_WAKE0_REASON=$finalWake0Reason"
Write-Output "FINAL_WAKE0_VECTOR=$finalWake0Vector"
