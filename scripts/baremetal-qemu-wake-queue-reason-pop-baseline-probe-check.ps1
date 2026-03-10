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
    Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_BASELINE_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying wake-queue reason-pop probe failed with exit code $probeExitCode"
}

$preCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_PRE_COUNT'
$preTask0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_PRE_TASK0'
$preTask1 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_PRE_TASK1'
$preTask2 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_PRE_TASK2'
$preTask3 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_PRE_TASK3'
$preVector0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_PRE_VECTOR0'
$preVector1 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_PRE_VECTOR1'
$preVector2 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_PRE_VECTOR2'
$preVector3 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_PRE_VECTOR3'

if ($null -in @($preCount, $preTask0, $preTask1, $preTask2, $preTask3, $preVector0, $preVector1, $preVector2, $preVector3)) {
    throw 'Missing expected baseline fields in wake-queue reason-pop probe output.'
}
if ($preCount -ne 4) { throw "Expected PRE_COUNT=4. got $preCount" }
if ($preTask0 -ne 1 -or $preTask1 -ne 2 -or $preTask2 -ne 3 -or $preTask3 -ne 4) {
    throw "Unexpected baseline task ordering: $preTask0,$preTask1,$preTask2,$preTask3"
}
if ($preVector0 -ne 0 -or $preVector1 -ne 13 -or $preVector2 -ne 13 -or $preVector3 -ne 31) {
    throw "Unexpected baseline vector ordering: $preVector0,$preVector1,$preVector2,$preVector3"
}

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_BASELINE_PROBE=pass'
Write-Output "PRE_COUNT=$preCount"
Write-Output "PRE_TASK0=$preTask0"
Write-Output "PRE_TASK1=$preTask1"
Write-Output "PRE_TASK2=$preTask2"
Write-Output "PRE_TASK3=$preTask3"
Write-Output "PRE_VECTOR0=$preVector0"
Write-Output "PRE_VECTOR1=$preVector1"
Write-Output "PRE_VECTOR2=$preVector2"
Write-Output "PRE_VECTOR3=$preVector3"
