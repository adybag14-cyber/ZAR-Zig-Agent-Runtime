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
    Write-Output "BAREMETAL_QEMU_RESET_VECTOR_COUNTERS_PRESERVE_LAST_VECTOR_PROBE=skipped"
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying vector-counter-reset probe failed with exit code $probeExitCode"
}

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

