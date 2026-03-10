param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-wake-queue-before-tick-probe-check.ps1"
$skipToken = 'BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_FIRST_CUTOFF_PROBE=skipped'

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
if ($probeText -match 'BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_PROBE=skipped') {
    Write-Output $skipToken
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying wake-queue before-tick probe failed with exit code $probeExitCode"
}

$task2Id = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_TASK2_ID'
$preTick1 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_PRE_TICK1'
$midCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_MID_COUNT'
$midTask1 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_MID_TASK1'
$midVector1 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_MID_VECTOR1'
$midTick0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_MID_TICK0'
if ($null -in @($task2Id,$preTick1,$midCount,$midTask1,$midVector1,$midTick0)) {
    throw 'Missing expected first-cutoff fields in wake-queue before-tick probe output.'
}
if ($midCount -ne 3) { throw "Expected MID_COUNT=3. got $midCount" }
if ($midTask1 -ne $task2Id) { throw "Expected MID_TASK1=$task2Id. got $midTask1" }
if ($midVector1 -ne 13) { throw "Expected MID_VECTOR1=13. got $midVector1" }
if ($midTick0 -ne $preTick1) { throw "Expected MID_TICK0=$preTick1. got $midTick0" }
Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_FIRST_CUTOFF_PROBE=pass'
Write-Output "MID_COUNT=$midCount"
Write-Output "MID_TASK1=$midTask1"
Write-Output "MID_VECTOR1=$midVector1"
Write-Output "MID_TICK0=$midTick0"

