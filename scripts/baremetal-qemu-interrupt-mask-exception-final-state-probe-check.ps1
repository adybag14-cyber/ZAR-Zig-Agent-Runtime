# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 40,
    [int] $GdbPort = 1348
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot 'baremetal-qemu-interrupt-mask-exception-probe-check.ps1'
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_INTERRUPT_MASK_EXCEPTION_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_INTERRUPT_MASK_EXCEPTION_FINAL_STATE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_INTERRUPT_MASK_EXCEPTION_FINAL_STATE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-interrupt-mask-exception-probe-check.ps1' `
    -FailureLabel 'Interrupt mask exception prerequisite' `
    -InvokeArgs @{ TimeoutSeconds = $TimeoutSeconds; GdbPort = $GdbPort }
$probeText = $probeState.Text

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $match = [regex]::Match($Text, '(?m)^' + [regex]::Escape($Name) + '=(-?\d+)\r?$')
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$required = @(
    @{ Name = 'BAREMETAL_QEMU_INTERRUPT_MASK_EXCEPTION_PROBE'; Expected = 'pass'; Type = 'string' },
    @{ Name = 'BAREMETAL_QEMU_INTERRUPT_MASK_EXCEPTION_PROBE_ACK'; Expected = 12; Type = 'int' },
    @{ Name = 'BAREMETAL_QEMU_INTERRUPT_MASK_EXCEPTION_PROBE_LAST_OPCODE'; Expected = 12; Type = 'int' },
    @{ Name = 'BAREMETAL_QEMU_INTERRUPT_MASK_EXCEPTION_PROBE_LAST_RESULT'; Expected = 0; Type = 'int' },
    @{ Name = 'BAREMETAL_QEMU_INTERRUPT_MASK_EXCEPTION_PROBE_SCHED_TASK_COUNT'; Expected = 1; Type = 'int' },
    @{ Name = 'BAREMETAL_QEMU_INTERRUPT_MASK_EXCEPTION_PROBE_TASK0_ID'; Expected = 1; Type = 'int' },
    @{ Name = 'BAREMETAL_QEMU_INTERRUPT_MASK_EXCEPTION_PROBE_TASK0_STATE'; Expected = 1; Type = 'int' },
    @{ Name = 'BAREMETAL_QEMU_INTERRUPT_MASK_EXCEPTION_PROBE_WAKE_QUEUE_COUNT'; Expected = 1; Type = 'int' },
    @{ Name = 'BAREMETAL_QEMU_INTERRUPT_MASK_EXCEPTION_PROBE_WAKE0_SEQ'; Expected = 1; Type = 'int' },
    @{ Name = 'BAREMETAL_QEMU_INTERRUPT_MASK_EXCEPTION_PROBE_WAKE0_TASK_ID'; Expected = 1; Type = 'int' },
    @{ Name = 'BAREMETAL_QEMU_INTERRUPT_MASK_EXCEPTION_PROBE_WAKE0_TIMER_ID'; Expected = 0; Type = 'int' },
    @{ Name = 'BAREMETAL_QEMU_INTERRUPT_MASK_EXCEPTION_PROBE_WAKE0_REASON'; Expected = 2; Type = 'int' },
    @{ Name = 'BAREMETAL_QEMU_INTERRUPT_MASK_EXCEPTION_PROBE_WAKE0_VECTOR'; Expected = 13; Type = 'int' },
    @{ Name = 'BAREMETAL_QEMU_INTERRUPT_MASK_EXCEPTION_PROBE_INTERRUPT_COUNT'; Expected = 1; Type = 'int' },
    @{ Name = 'BAREMETAL_QEMU_INTERRUPT_MASK_EXCEPTION_PROBE_LAST_INTERRUPT_VECTOR'; Expected = 13; Type = 'int' },
    @{ Name = 'BAREMETAL_QEMU_INTERRUPT_MASK_EXCEPTION_PROBE_EXCEPTION_COUNT'; Expected = 1; Type = 'int' },
    @{ Name = 'BAREMETAL_QEMU_INTERRUPT_MASK_EXCEPTION_PROBE_LAST_EXCEPTION_VECTOR'; Expected = 13; Type = 'int' },
    @{ Name = 'BAREMETAL_QEMU_INTERRUPT_MASK_EXCEPTION_PROBE_LAST_EXCEPTION_CODE'; Expected = 51966; Type = 'int' }
)

foreach ($item in $required) {
    if ($item.Type -eq 'string') {
        $match = [regex]::Match($outputText, '(?m)^' + [regex]::Escape($item.Name) + '=(.+)$')
        if (-not $match.Success) { throw "Missing output value for $($item.Name)" }
        if ($match.Groups[1].Value.Trim() -ne $item.Expected) { throw "Unexpected $($item.Name): got $($match.Groups[1].Value.Trim()) expected $($item.Expected)" }
    } else {
        $value = Extract-IntValue -Text $outputText -Name $item.Name
        if ($null -eq $value) { throw "Missing output value for $($item.Name)" }
        if ($value -ne $item.Expected) { throw "Unexpected $($item.Name): got $value expected $($item.Expected)" }
    }
}

Write-Output 'BAREMETAL_QEMU_INTERRUPT_MASK_EXCEPTION_FINAL_STATE_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_INTERRUPT_MASK_EXCEPTION_FINAL_STATE_PROBE_SOURCE=baremetal-qemu-interrupt-mask-exception-probe-check.ps1'
Write-Output 'ACK=12'
Write-Output 'LAST_OPCODE=12'
Write-Output 'LAST_RESULT=0'
Write-Output 'SCHED_TASK_COUNT=1'
Write-Output 'TASK0_ID=1'
Write-Output 'TASK0_STATE=1'
Write-Output 'WAKE_QUEUE_COUNT=1'
Write-Output 'WAKE0_SEQ=1'
Write-Output 'WAKE0_TASK_ID=1'
Write-Output 'WAKE0_TIMER_ID=0'
Write-Output 'WAKE0_REASON=2'
Write-Output 'WAKE0_VECTOR=13'
Write-Output 'INTERRUPT_COUNT=1'
Write-Output 'LAST_INTERRUPT_VECTOR=13'
Write-Output 'EXCEPTION_COUNT=1'
Write-Output 'LAST_EXCEPTION_VECTOR=13'
Write-Output 'LAST_EXCEPTION_CODE=51966'
