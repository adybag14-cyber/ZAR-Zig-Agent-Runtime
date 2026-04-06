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
    -SkippedReceipt 'BAREMETAL_QEMU_RESET_VECTOR_COUNTERS_PRESERVE_LAST_VECTOR_PROBE' `
    -FailureLabel 'vector-counter-reset' `
    -EchoOnSuccess:$true `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true
$probeText = $probeState.Text
$preLastInterruptVector = Extract-IntValue -Text $probeText -Name "BAREMETAL_QEMU_VECTOR_COUNTER_RESET_PRE_LAST_INTERRUPT_VECTOR"
$preLastExceptionVector = Extract-IntValue -Text $probeText -Name "BAREMETAL_QEMU_VECTOR_COUNTER_RESET_PRE_LAST_EXCEPTION_VECTOR"
$preLastExceptionCode = Extract-IntValue -Text $probeText -Name "BAREMETAL_QEMU_VECTOR_COUNTER_RESET_PRE_LAST_EXCEPTION_CODE"
$postLastInterruptVector = Extract-IntValue -Text $probeText -Name "BAREMETAL_QEMU_VECTOR_COUNTER_RESET_POST_LAST_INTERRUPT_VECTOR"
$postLastExceptionVector = Extract-IntValue -Text $probeText -Name "BAREMETAL_QEMU_VECTOR_COUNTER_RESET_POST_LAST_EXCEPTION_VECTOR"
$postLastExceptionCode = Extract-IntValue -Text $probeText -Name "BAREMETAL_QEMU_VECTOR_COUNTER_RESET_POST_LAST_EXCEPTION_CODE"

if ($null -in @($preLastInterruptVector, $preLastExceptionVector, $preLastExceptionCode, $postLastInterruptVector, $postLastExceptionVector, $postLastExceptionCode)) {
    throw "Missing expected vector-counter last-vector fields in probe output."
}
if ($postLastInterruptVector -ne $preLastInterruptVector) {
    throw "Last interrupt vector drifted across vector-counter reset. pre=$preLastInterruptVector post=$postLastInterruptVector"
}
if ($postLastExceptionVector -ne $preLastExceptionVector) {
    throw "Last exception vector drifted across vector-counter reset. pre=$preLastExceptionVector post=$postLastExceptionVector"
}
if ($postLastExceptionCode -ne $preLastExceptionCode) {
    throw "Last exception code drifted across vector-counter reset. pre=$preLastExceptionCode post=$postLastExceptionCode"
}

Write-Output "BAREMETAL_QEMU_RESET_VECTOR_COUNTERS_PRESERVE_LAST_VECTOR_PROBE=pass"
Write-Output "PRE_LAST_INTERRUPT_VECTOR=$preLastInterruptVector"
Write-Output "POST_LAST_INTERRUPT_VECTOR=$postLastInterruptVector"
Write-Output "PRE_LAST_EXCEPTION_VECTOR=$preLastExceptionVector"
Write-Output "POST_LAST_EXCEPTION_VECTOR=$postLastExceptionVector"
Write-Output "PRE_LAST_EXCEPTION_CODE=$preLastExceptionCode"
Write-Output "POST_LAST_EXCEPTION_CODE=$postLastExceptionCode"

