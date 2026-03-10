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
    Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_FIRST_MATCH_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying wake-queue reason-pop probe failed with exit code $probeExitCode"
}

$midCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_MID_COUNT'
$midTask0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_MID_TASK0'
$midTask1 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_MID_TASK1'
$midTask2 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_MID_TASK2'
$midVector0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_MID_VECTOR0'
$midVector1 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_MID_VECTOR1'
$midVector2 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_MID_VECTOR2'

if ($null -in @($midCount, $midTask0, $midTask1, $midTask2, $midVector0, $midVector1, $midVector2)) {
    throw 'Missing expected first-match fields in wake-queue reason-pop probe output.'
}
if ($midCount -ne 3) { throw "Expected MID_COUNT=3. got $midCount" }
if ($midTask0 -ne 1 -or $midTask1 -ne 3 -or $midTask2 -ne 4) {
    throw "Unexpected first-match task ordering: $midTask0,$midTask1,$midTask2"
}
if ($midVector0 -ne 0 -or $midVector1 -ne 13 -or $midVector2 -ne 31) {
    throw "Unexpected first-match vector ordering: $midVector0,$midVector1,$midVector2"
}

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_FIRST_MATCH_PROBE=pass'
Write-Output "MID_COUNT=$midCount"
Write-Output "MID_TASK0=$midTask0"
Write-Output "MID_TASK1=$midTask1"
Write-Output "MID_TASK2=$midTask2"
Write-Output "MID_VECTOR0=$midVector0"
Write-Output "MID_VECTOR1=$midVector1"
Write-Output "MID_VECTOR2=$midVector2"
