param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-wake-queue-reason-overflow-probe-check.ps1"

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
if ($probeText -match 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_OVERFLOW_PROBE=skipped') {
    Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_OVERFLOW_INTERRUPT_DRAIN_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying wake-queue-reason-overflow probe failed with exit code $probeExitCode"
}

$postInterruptCount = Extract-IntValue -Text $probeText -Name 'POST_INTERRUPT_COUNT'
$postInterruptHead = Extract-IntValue -Text $probeText -Name 'POST_INTERRUPT_HEAD'
$postInterruptTail = Extract-IntValue -Text $probeText -Name 'POST_INTERRUPT_TAIL'
$postInterruptOverflow = Extract-IntValue -Text $probeText -Name 'POST_INTERRUPT_OVERFLOW'

if ($null -in @($postInterruptCount, $postInterruptHead, $postInterruptTail, $postInterruptOverflow)) {
    throw 'Missing post-interrupt drain summary fields in wake-queue-reason-overflow probe output.'
}
if ($postInterruptCount -ne 32 -or $postInterruptHead -ne 32 -or $postInterruptTail -ne 0 -or $postInterruptOverflow -ne 2) {
    throw "Unexpected POST_INTERRUPT summary: $postInterruptCount/$postInterruptHead/$postInterruptTail/$postInterruptOverflow"
}

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_OVERFLOW_INTERRUPT_DRAIN_PROBE=pass'
Write-Output "POST_INTERRUPT_COUNT=$postInterruptCount"
Write-Output "POST_INTERRUPT_HEAD=$postInterruptHead"
Write-Output "POST_INTERRUPT_TAIL=$postInterruptTail"
Write-Output "POST_INTERRUPT_OVERFLOW=$postInterruptOverflow"
