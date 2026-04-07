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
    -SkippedReceipt 'BAREMETAL_QEMU_INTERRUPT_MASK_EXCEPTION_MASKED_INTERRUPT_BLOCKED_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_INTERRUPT_MASK_EXCEPTION_MASKED_INTERRUPT_BLOCKED_PROBE_SOURCE' `
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
    @{ Name = 'BAREMETAL_QEMU_INTERRUPT_MASK_EXCEPTION_PROBE_MASK_IGNORED_AFTER_MASK'; Expected = 1; Type = 'int' },
    @{ Name = 'BAREMETAL_QEMU_INTERRUPT_MASK_EXCEPTION_PROBE_MASKED_INTERRUPT_IGNORED_COUNT'; Expected = 1; Type = 'int' },
    @{ Name = 'BAREMETAL_QEMU_INTERRUPT_MASK_EXCEPTION_PROBE_MASKED_VECTOR_200_IGNORED'; Expected = 1; Type = 'int' },
    @{ Name = 'BAREMETAL_QEMU_INTERRUPT_MASK_EXCEPTION_PROBE_LAST_MASKED_INTERRUPT_VECTOR'; Expected = 200; Type = 'int' },
    @{ Name = 'BAREMETAL_QEMU_INTERRUPT_MASK_EXCEPTION_PROBE_WAKE_QUEUE_COUNT_AFTER_MASK'; Expected = 0; Type = 'int' }
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

Write-Output 'BAREMETAL_QEMU_INTERRUPT_MASK_EXCEPTION_MASKED_INTERRUPT_BLOCKED_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_INTERRUPT_MASK_EXCEPTION_MASKED_INTERRUPT_BLOCKED_PROBE_SOURCE=baremetal-qemu-interrupt-mask-exception-probe-check.ps1'
Write-Output 'MASK_IGNORED_AFTER_MASK=1'
Write-Output 'MASKED_INTERRUPT_IGNORED_COUNT=1'
Write-Output 'MASKED_VECTOR_200_IGNORED=1'
Write-Output 'LAST_MASKED_INTERRUPT_VECTOR=200'
Write-Output 'WAKE_QUEUE_COUNT_AFTER_MASK=0'
