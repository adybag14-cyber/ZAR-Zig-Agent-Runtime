param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-wake-queue-overflow-probe-check.ps1"

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $pattern = '(?m)^' + [regex]::Escape($Name) + '=(-?\d+)\r?$'
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$probeOutput = if ($SkipBuild) { & $probe -SkipBuild -TimeoutSeconds 90 2>&1 } else { & $probe -TimeoutSeconds 90 2>&1 }
$probeExitCode = $LASTEXITCODE
$probeText = ($probeOutput | Out-String)
$probeOutput | Write-Output
if ($probeText -match 'BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_PROBE=skipped') {
    Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_NEWEST_ENTRY_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying wake-queue-overflow probe failed with exit code $probeExitCode"
}

$taskId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_TASK_ID'
$oldestTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_OLDEST_TICK'
$newestSeq = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_NEWEST_SEQ'
$newestTaskId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_NEWEST_TASK_ID'
$newestReason = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_NEWEST_REASON'
$newestTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_NEWEST_TICK'

if ($null -in @($taskId, $oldestTick, $newestSeq, $newestTaskId, $newestReason, $newestTick)) {
    throw 'Missing expected newest-entry fields in wake-queue-overflow probe output.'
}
if ($newestSeq -ne 66) { throw "Expected NEWEST_SEQ=66. got $newestSeq" }
if ($newestTaskId -ne $taskId) { throw "Expected NEWEST_TASK_ID=$taskId. got $newestTaskId" }
if ($newestReason -ne 3) { throw "Expected NEWEST_REASON=3. got $newestReason" }
if ($newestTick -le $oldestTick) { throw "Expected NEWEST_TICK > OLDEST_TICK. got oldest=$oldestTick newest=$newestTick" }

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_NEWEST_ENTRY_PROBE=pass'
Write-Output "NEWEST_SEQ=$newestSeq"
Write-Output "NEWEST_TASK_ID=$newestTaskId"
Write-Output "NEWEST_REASON=$newestReason"
Write-Output "NEWEST_TICK=$newestTick"
