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
    Write-Output 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_INTERRUPT_IMMEDIATE_WAKE_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying interrupt-timeout disable-interrupt probe failed with exit code $probeExitCode"
}

$disabledWakeQueueCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_INTERRUPT_PROBE_DISABLED_WAKE_QUEUE_COUNT'
$disabledWake0Reason = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_INTERRUPT_PROBE_DISABLED_WAKE0_REASON'
$disabledWake0Vector = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_INTERRUPT_PROBE_DISABLED_WAKE0_VECTOR'
$disabledTask0State = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_INTERRUPT_PROBE_DISABLED_TASK0_STATE'
$disabledInterruptCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_INTERRUPT_PROBE_DISABLED_INTERRUPT_COUNT'
if ($null -in @($disabledWakeQueueCount, $disabledWake0Reason, $disabledWake0Vector, $disabledTask0State, $disabledInterruptCount)) {
    throw 'Missing immediate-wake fields in probe output.'
}
if ($disabledWakeQueueCount -ne 1) { throw "Expected one queued wake immediately after interrupt. got $disabledWakeQueueCount" }
if ($disabledWake0Reason -ne 2) { throw "Expected interrupt wake reason (2). got $disabledWake0Reason" }
if ($disabledWake0Vector -ne 31) { throw "Expected interrupt vector 31. got $disabledWake0Vector" }
if ($disabledTask0State -ne 1) { throw "Expected task ready state (1) after interrupt wake. got $disabledTask0State" }
if ($disabledInterruptCount -ne 1) { throw "Expected one delivered interrupt. got $disabledInterruptCount" }

Write-Output 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_INTERRUPT_IMMEDIATE_WAKE_PROBE=pass'
Write-Output "DISABLED_WAKE_QUEUE_COUNT=$disabledWakeQueueCount"
Write-Output "DISABLED_WAKE0_REASON=$disabledWake0Reason"
Write-Output "DISABLED_WAKE0_VECTOR=$disabledWake0Vector"
Write-Output "DISABLED_TASK0_STATE=$disabledTask0State"
Write-Output "DISABLED_INTERRUPT_COUNT=$disabledInterruptCount"
