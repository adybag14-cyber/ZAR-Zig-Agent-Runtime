# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-wake-queue-summary-age-probe-check.ps1"
$skipToken = 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_BASELINE_PROBE=skipped'

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
if ($probeText -match 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE=skipped') {
    Write-Output $skipToken
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying wake-queue summary/age probe failed with exit code $probeExitCode"
}

$preCurrentTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_PRE_CURRENT_TICK'
$preLen = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_PRE_LEN'
$preTask0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_PRE_TASK0'
$preTask1 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_PRE_TASK1'
$preTask2 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_PRE_TASK2'
$preTask3 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_PRE_TASK3'
$preTask4 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_PRE_TASK4'
$finalQueueCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_FINAL_QUEUE_COUNT'
$finalStableTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_FINAL_STABLE_TICK'
if ($null -in @($preCurrentTick,$preLen,$preTask0,$preTask1,$preTask2,$preTask3,$preTask4,$finalQueueCount,$finalStableTick)) {
    throw 'Missing expected baseline fields in wake-queue summary/age probe output.'
}
if ($preCurrentTick -ne 21) { throw "Expected PRE_CURRENT_TICK=21. got $preCurrentTick" }
if ($preLen -ne 5) { throw "Expected PRE_LEN=5. got $preLen" }
if ($preTask0 -ne 1 -or $preTask1 -ne 2 -or $preTask2 -ne 3 -or $preTask3 -ne 4 -or $preTask4 -ne 5) {
    throw "Unexpected baseline task ordering: $preTask0,$preTask1,$preTask2,$preTask3,$preTask4"
}
if ($finalQueueCount -ne 4) { throw "Expected FINAL_QUEUE_COUNT=4. got $finalQueueCount" }
if ($finalStableTick -lt 26) { throw "Expected FINAL_STABLE_TICK >= 26. got $finalStableTick" }

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_BASELINE_PROBE=pass'
Write-Output "PRE_CURRENT_TICK=$preCurrentTick"
Write-Output "PRE_LEN=$preLen"
Write-Output "PRE_TASK0=$preTask0"
Write-Output "PRE_TASK1=$preTask1"
Write-Output "PRE_TASK2=$preTask2"
Write-Output "PRE_TASK3=$preTask3"
Write-Output "PRE_TASK4=$preTask4"
Write-Output "FINAL_QUEUE_COUNT=$finalQueueCount"
Write-Output "FINAL_STABLE_TICK=$finalStableTick"