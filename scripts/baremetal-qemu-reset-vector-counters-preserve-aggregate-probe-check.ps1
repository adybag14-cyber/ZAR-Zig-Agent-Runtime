# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-vector-counter-reset-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $pattern = '(?m)^\{0}=(-?\d+)\r?$' -f $Name
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_VECTOR_COUNTER_RESET_PROBE=skipped\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_RESET_VECTOR_COUNTERS_PRESERVE_AGGREGATE_PROBE' `
    -FailureLabel 'vector-counter-reset' `
    -EchoOnSuccess:$true `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true
$probeText = $probeState.Text
$preInterruptCount = Extract-IntValue -Text $probeText -Name "BAREMETAL_QEMU_VECTOR_COUNTER_RESET_PRE_INTERRUPT_COUNT"
$preExceptionCount = Extract-IntValue -Text $probeText -Name "BAREMETAL_QEMU_VECTOR_COUNTER_RESET_PRE_EXCEPTION_COUNT"
$postInterruptCount = Extract-IntValue -Text $probeText -Name "BAREMETAL_QEMU_VECTOR_COUNTER_RESET_POST_INTERRUPT_COUNT"
$postExceptionCount = Extract-IntValue -Text $probeText -Name "BAREMETAL_QEMU_VECTOR_COUNTER_RESET_POST_EXCEPTION_COUNT"

if ($null -in @($preInterruptCount, $preExceptionCount, $postInterruptCount, $postExceptionCount)) {
    throw "Missing expected vector-counter aggregate fields in probe output."
}
if ($postInterruptCount -ne $preInterruptCount) {
    throw "Interrupt aggregate drifted across vector-counter reset. pre=$preInterruptCount post=$postInterruptCount"
}
if ($postExceptionCount -ne $preExceptionCount) {
    throw "Exception aggregate drifted across vector-counter reset. pre=$preExceptionCount post=$postExceptionCount"
}

Write-Output "BAREMETAL_QEMU_RESET_VECTOR_COUNTERS_PRESERVE_AGGREGATE_PROBE=pass"
Write-Output "PRE_INTERRUPT_COUNT=$preInterruptCount"
Write-Output "POST_INTERRUPT_COUNT=$postInterruptCount"
Write-Output "PRE_EXCEPTION_COUNT=$preExceptionCount"
Write-Output "POST_EXCEPTION_COUNT=$postExceptionCount"

