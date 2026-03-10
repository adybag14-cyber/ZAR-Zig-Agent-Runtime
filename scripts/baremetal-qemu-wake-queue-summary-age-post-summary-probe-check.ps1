param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-wake-queue-summary-age-probe-check.ps1"

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
    Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_POST_SUMMARY_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying wake-queue summary/age probe failed with exit code $probeExitCode"
}

$postLen = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_POST_LEN'
$postTask0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_POST_TASK0'
$postTask1 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_POST_TASK1'
$postTask2 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_POST_TASK2'
$postTask3 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_POST_TASK3'
$len = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_POST_SUMMARY_LEN'
$overflow = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_POST_SUMMARY_OVERFLOW'
$timerCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_POST_SUMMARY_TIMER_COUNT'
$interruptCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_POST_SUMMARY_INTERRUPT_COUNT'
$manualCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_POST_SUMMARY_MANUAL_COUNT'
$nonzeroVectorCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_POST_SUMMARY_NONZERO_VECTOR_COUNT'
$staleCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_POST_SUMMARY_STALE_COUNT'
$oldestTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_POST_SUMMARY_OLDEST_TICK'
$newestTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_POST_SUMMARY_NEWEST_TICK'
if ($null -in @($postLen,$postTask0,$postTask1,$postTask2,$postTask3,$len,$overflow,$timerCount,$interruptCount,$manualCount,$nonzeroVectorCount,$staleCount,$oldestTick,$newestTick)) {
    throw 'Missing expected post-summary fields in wake-queue summary/age probe output.'
}
if ($postLen -ne 4 -or $postTask0 -ne 1 -or $postTask1 -ne 3 -or $postTask2 -ne 4 -or $postTask3 -ne 5) {
    throw "Unexpected post-drain task ordering: len=$postLen tasks=$postTask0,$postTask1,$postTask2,$postTask3"
}
if ($len -ne 4 -or $overflow -ne 0 -or $timerCount -ne 1 -or $interruptCount -ne 2 -or $manualCount -ne 1 -or $nonzeroVectorCount -ne 2 -or $staleCount -ne 4 -or $oldestTick -ne 8 -or $newestTick -ne 20) {
    throw "Unexpected post-summary snapshot: len=$len overflow=$overflow timer=$timerCount interrupt=$interruptCount manual=$manualCount nonzero=$nonzeroVectorCount stale=$staleCount oldest=$oldestTick newest=$newestTick"
}

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_POST_SUMMARY_PROBE=pass'
Write-Output "POST_LEN=$postLen"
Write-Output "POST_TASK0=$postTask0"
Write-Output "POST_TASK1=$postTask1"
Write-Output "POST_TASK2=$postTask2"
Write-Output "POST_TASK3=$postTask3"
Write-Output "POST_SUMMARY_INTERRUPT_COUNT=$interruptCount"
Write-Output "POST_SUMMARY_MANUAL_COUNT=$manualCount"