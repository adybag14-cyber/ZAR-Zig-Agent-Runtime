param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-wake-queue-batch-pop-probe-check.ps1"

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
if ($probeText -match 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_PROBE=skipped') {
    Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_OVERFLOW_BASELINE_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying wake-queue-batch-pop probe failed with exit code $probeExitCode"
}

$wakeCycles = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_WAKE_CYCLES'
$taskId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_TASK_ID'
$taskState = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_TASK_STATE'
$ticks = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_TICKS'

if ($null -in @($wakeCycles, $taskId, $taskState, $ticks)) {
    throw 'Missing expected overflow-baseline fields in wake-queue-batch-pop probe output.'
}
if ($wakeCycles -ne 66) { throw "Expected WAKE_CYCLES=66. got $wakeCycles" }
if ($taskId -le 0) { throw "Expected TASK_ID > 0. got $taskId" }
if ($taskState -ne 1) { throw "Expected TASK_STATE=1. got $taskState" }
if ($ticks -lt 141) { throw "Expected TICKS >= 141. got $ticks" }

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_OVERFLOW_BASELINE_PROBE=pass'
Write-Output "WAKE_CYCLES=$wakeCycles"
Write-Output "TASK_ID=$taskId"
Write-Output "TASK_STATE=$taskState"
Write-Output "TICKS=$ticks"
