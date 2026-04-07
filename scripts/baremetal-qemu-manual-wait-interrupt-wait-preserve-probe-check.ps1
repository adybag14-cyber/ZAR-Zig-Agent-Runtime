# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-manual-wait-interrupt-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $match = [regex]::Match($Text, '(?m)^' + [regex]::Escape($Name) + '=(-?\\d+)\\r?$')
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_WAIT_PRESERVE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_WAIT_PRESERVE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-manual-wait-interrupt-probe-check.ps1' `
    -FailureLabel 'manual-wait interrupt' `
    -EchoOnSuccess:$true `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true `
    -EmitSkippedSourceReceipt:$true
$probeText = $probeState.Text

$waitState = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_WAIT_STATE_BEFORE_INTERRUPT'
$waitTaskCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_WAIT_TASK_COUNT_BEFORE_INTERRUPT'
$waitKind = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_WAIT_KIND_BEFORE_INTERRUPT'
if ($null -in @($waitState, $waitTaskCount, $waitKind)) { throw 'Missing wait-preserve fields in manual-wait-interrupt probe output.' }
if ($waitState -ne 6) { throw "Expected WAIT_STATE_BEFORE_INTERRUPT=6, got $waitState" }
if ($waitTaskCount -ne 0) { throw "Expected WAIT_TASK_COUNT_BEFORE_INTERRUPT=0, got $waitTaskCount" }
if ($waitKind -ne 1) { throw "Expected WAIT_KIND_BEFORE_INTERRUPT=1, got $waitKind" }
Write-Output 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_WAIT_PRESERVE_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_WAIT_PRESERVE_PROBE_SOURCE=baremetal-qemu-manual-wait-interrupt-probe-check.ps1'
Write-Output 'WAIT_STATE_BEFORE_INTERRUPT=6'
Write-Output 'WAIT_TASK_COUNT_BEFORE_INTERRUPT=0'
Write-Output 'WAIT_KIND_BEFORE_INTERRUPT=1'
