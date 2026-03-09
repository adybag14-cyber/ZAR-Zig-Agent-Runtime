param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-vector-counter-reset-probe-check.ps1"

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
if ($probeText -match 'BAREMETAL_QEMU_VECTOR_COUNTER_RESET_PROBE=skipped') {
    Write-Output "BAREMETAL_QEMU_RESET_VECTOR_COUNTERS_PRESERVE_AGGREGATE_PROBE=skipped"
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying vector-counter-reset probe failed with exit code $probeExitCode"
}

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

