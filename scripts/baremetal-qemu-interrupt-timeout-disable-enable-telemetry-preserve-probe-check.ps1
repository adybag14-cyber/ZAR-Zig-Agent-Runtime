param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-interrupt-timeout-disable-enable-probe-check.ps1"

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
    Write-Output 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_ENABLE_TELEMETRY_PRESERVE_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying interrupt-timeout disable-enable probe failed with exit code $probeExitCode"
}

$interruptCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_ENABLE_PROBE_INTERRUPT_COUNT'
$timerLastInterruptCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_ENABLE_PROBE_TIMER_LAST_INTERRUPT_COUNT'
$lastInterruptVector = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_ENABLE_PROBE_LAST_INTERRUPT_VECTOR'
$wake0Reason = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_ENABLE_PROBE_WAKE0_REASON'
$wake0Vector = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_ENABLE_PROBE_WAKE0_VECTOR'

if ($null -in @($interruptCount, $timerLastInterruptCount, $lastInterruptVector, $wake0Reason, $wake0Vector)) {
    throw 'Missing expected telemetry-preservation fields in probe output.'
}
if ($interruptCount -ne 0) {
    throw "Expected no interrupt delivery in the deferred timer-only path. got $interruptCount"
}
if ($timerLastInterruptCount -ne 0) {
    throw "Expected timer interrupt telemetry to remain zero in the deferred timer-only path. got $timerLastInterruptCount"
}
if ($lastInterruptVector -ne 0) {
    throw "Expected last interrupt vector to remain zero in the deferred timer-only path. got $lastInterruptVector"
}
if ($wake0Reason -ne 1 -or $wake0Vector -ne 0) {
    throw "Expected deferred wake to remain timer-only while preserving zero interrupt telemetry. got reason=$wake0Reason vector=$wake0Vector"
}

Write-Output 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_ENABLE_TELEMETRY_PRESERVE_PROBE=pass'
Write-Output "INTERRUPT_COUNT=$interruptCount"
Write-Output "TIMER_LAST_INTERRUPT_COUNT=$timerLastInterruptCount"
Write-Output "LAST_INTERRUPT_VECTOR=$lastInterruptVector"
Write-Output "WAKE0_REASON=$wake0Reason"
Write-Output "WAKE0_VECTOR=$wake0Vector"
