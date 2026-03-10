param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-wake-queue-reason-pop-probe-check.ps1"

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
if ($probeText -match 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_PROBE=skipped') {
    Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_INVALID_PRESERVE_STATE_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying wake-queue reason-pop probe failed with exit code $probeExitCode"
}

$finalCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_FINAL_COUNT'
$finalTask0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_FINAL_TASK0'
$finalTask1 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_FINAL_TASK1'
$finalVector0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_FINAL_VECTOR0'
$finalVector1 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_FINAL_VECTOR1'

if ($null -in @($finalCount, $finalTask0, $finalTask1, $finalVector0, $finalVector1)) {
    throw 'Missing expected invalid-preserve-state fields in wake-queue reason-pop probe output.'
}
if ($finalCount -ne 1) { throw "Expected FINAL_COUNT=1. got $finalCount" }
if ($finalTask0 -ne 1 -or $finalTask1 -ne 0) {
    throw "Unexpected final task state after invalid reason: $finalTask0,$finalTask1"
}
if ($finalVector0 -ne 0 -or $finalVector1 -ne 0) {
    throw "Unexpected final vector state after invalid reason: $finalVector0,$finalVector1"
}

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_INVALID_PRESERVE_STATE_PROBE=pass'
Write-Output "FINAL_COUNT=$finalCount"
Write-Output "FINAL_TASK0=$finalTask0"
Write-Output "FINAL_TASK1=$finalTask1"
Write-Output "FINAL_VECTOR0=$finalVector0"
Write-Output "FINAL_VECTOR1=$finalVector1"
