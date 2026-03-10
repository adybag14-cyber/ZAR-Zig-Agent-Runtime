param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-wake-queue-before-tick-probe-check.ps1"
$skipToken = 'BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_NOTFOUND_PRESERVE_STATE_PROBE=skipped'

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

$task4Id = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_TASK4_ID'
$postCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_POST_COUNT'
$postTask0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_POST_TASK0'
$postVector0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_POST_VECTOR0'
$postTick0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_POST_TICK0'
$finalCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_FINAL_COUNT'
$finalTask0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_FINAL_TASK0'
$finalVector0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_FINAL_VECTOR0'
$finalTick0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_FINAL_TICK0'
if ($null -in @($task4Id,$postCount,$postTask0,$postVector0,$postTick0,$finalCount,$finalTask0,$finalVector0,$finalTick0)) {
    throw 'Missing expected preserve-state fields in wake-queue before-tick probe output.'
}
if ($postCount -ne 1 -or $finalCount -ne 1) {
    throw "Expected POST_COUNT=1 and FINAL_COUNT=1. got $postCount,$finalCount"
}
if ($postTask0 -ne $task4Id -or $finalTask0 -ne $task4Id) {
    throw "Unexpected preserved final task state: POST=$postTask0 FINAL=$finalTask0"
}
if ($postVector0 -ne 31 -or $finalVector0 -ne 31) {
    throw "Unexpected preserved final vector state: POST=$postVector0 FINAL=$finalVector0"
}
if ($finalTick0 -ne $postTick0) {
    throw "Expected FINAL_TICK0=$postTick0. got $finalTick0"
}
Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_NOTFOUND_PRESERVE_STATE_PROBE=pass'
Write-Output "FINAL_COUNT=$finalCount"
Write-Output "FINAL_TASK0=$finalTask0"
Write-Output "FINAL_VECTOR0=$finalVector0"
Write-Output "FINAL_TICK0=$finalTick0"
