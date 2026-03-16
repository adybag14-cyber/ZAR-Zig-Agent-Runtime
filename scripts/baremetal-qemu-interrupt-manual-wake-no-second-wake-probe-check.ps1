# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-interrupt-manual-wake-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $match = [regex]::Match($Text, '(?m)^' + [regex]::Escape($Name) + '=(-?\d+)\r?$')
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$probeOutput = if ($SkipBuild) { & $probe -SkipBuild 2>&1 } else { & $probe 2>&1 }
$probeExitCode = $LASTEXITCODE
$probeText = ($probeOutput | Out-String)
if ($probeText -match '(?m)^BAREMETAL_QEMU_INTERRUPT_MANUAL_WAKE_PROBE=skipped\r?$') {
    if ($probeText) { Write-Output $probeText.TrimEnd() }
    Write-Output 'BAREMETAL_QEMU_INTERRUPT_MANUAL_WAKE_NO_SECOND_WAKE_PROBE=skipped'
    Write-Output 'BAREMETAL_QEMU_INTERRUPT_MANUAL_WAKE_NO_SECOND_WAKE_PROBE_SOURCE=baremetal-qemu-interrupt-manual-wake-probe-check.ps1'
    exit 0
}
if ($probeExitCode -ne 0) {
    if ($probeText) { Write-Output $probeText.TrimEnd() }
    throw "Underlying interrupt-manual-wake probe failed with exit code $probeExitCode"
}
$interruptCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MANUAL_WAKE_PROBE_INTERRUPT_COUNT'
$lastInterruptVector = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MANUAL_WAKE_PROBE_LAST_INTERRUPT_VECTOR'
$wakeQueueCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MANUAL_WAKE_PROBE_WAKE_QUEUE_COUNT'
$wake0Seq = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MANUAL_WAKE_PROBE_WAKE0_SEQ'
if ($null -in @($interruptCount,$lastInterruptVector,$wakeQueueCount,$wake0Seq)) {
    throw 'Missing expected interrupt-manual-wake no-second-wake fields in probe output.'
}
if ($interruptCount -ne 1) { throw "Expected INTERRUPT_COUNT=1. got $interruptCount" }
if ($lastInterruptVector -ne 200) { throw "Expected LAST_INTERRUPT_VECTOR=200. got $lastInterruptVector" }
if ($wakeQueueCount -ne 1) { throw "Expected WAKE_QUEUE_COUNT=1. got $wakeQueueCount" }
if ($wake0Seq -ne 1) { throw "Expected WAKE0_SEQ=1. got $wake0Seq" }
Write-Output 'BAREMETAL_QEMU_INTERRUPT_MANUAL_WAKE_NO_SECOND_WAKE_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_INTERRUPT_MANUAL_WAKE_NO_SECOND_WAKE_PROBE_SOURCE=baremetal-qemu-interrupt-manual-wake-probe-check.ps1'
Write-Output "INTERRUPT_COUNT=$interruptCount"
Write-Output "LAST_INTERRUPT_VECTOR=$lastInterruptVector"
Write-Output "WAKE_QUEUE_COUNT=$wakeQueueCount"
Write-Output "WAKE0_SEQ=$wake0Seq"
