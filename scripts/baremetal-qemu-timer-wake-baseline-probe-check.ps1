param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-timer-wake-probe-check.ps1"

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
if ($probeText -match 'BAREMETAL_QEMU_TIMER_WAKE_PROBE=skipped') {
    Write-Output 'BAREMETAL_QEMU_TIMER_WAKE_BASELINE_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying timer-wake probe failed with exit code $probeExitCode"
}

$artifactMatch = [regex]::Match($probeText, '(?m)^BAREMETAL_QEMU_ARTIFACT=(.+)\r?$')
$startAddrMatch = [regex]::Match($probeText, '(?m)^BAREMETAL_QEMU_TIMER_WAKE_PROBE_START_ADDR=0x[0-9a-fA-F]+\r?$')
$statusAddrMatch = [regex]::Match($probeText, '(?m)^BAREMETAL_QEMU_TIMER_WAKE_PROBE_STATUS_ADDR=0x[0-9a-fA-F]+\r?$')
$mailboxAddrMatch = [regex]::Match($probeText, '(?m)^BAREMETAL_QEMU_TIMER_WAKE_PROBE_MAILBOX_ADDR=0x[0-9a-fA-F]+\r?$')
$hitStart = [regex]::Match($probeText, '(?m)^BAREMETAL_QEMU_TIMER_WAKE_PROBE_HIT_START=(True|False)\r?$')
$hitAfter = [regex]::Match($probeText, '(?m)^BAREMETAL_QEMU_TIMER_WAKE_PROBE_HIT_AFTER_TIMER_WAKE=(True|False)\r?$')
$ticks = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_WAKE_PROBE_TICKS'
$schedTaskCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_WAKE_PROBE_SCHED_TASK_COUNT'
$task0Id = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_WAKE_PROBE_TASK0_ID'
$task0Priority = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_WAKE_PROBE_TASK0_PRIORITY'
$task0Budget = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_WAKE_PROBE_TASK0_BUDGET'

if (-not $artifactMatch.Success) { throw 'Missing artifact path in timer-wake probe output.' }
if (-not $startAddrMatch.Success) { throw 'Missing start address in timer-wake probe output.' }
if (-not $statusAddrMatch.Success) { throw 'Missing status address in timer-wake probe output.' }
if (-not $mailboxAddrMatch.Success) { throw 'Missing mailbox address in timer-wake probe output.' }
if (-not $hitStart.Success -or $hitStart.Groups[1].Value -ne 'True') { throw 'Expected HIT_START=True.' }
if (-not $hitAfter.Success -or $hitAfter.Groups[1].Value -ne 'True') { throw 'Expected HIT_AFTER_TIMER_WAKE=True.' }
if ($null -in @($ticks, $schedTaskCount, $task0Id, $task0Priority, $task0Budget)) {
    throw 'Missing expected baseline integer fields in timer-wake probe output.'
}
if ($ticks -lt 5) { throw "Expected TICKS>=5. got $ticks" }
if ($schedTaskCount -ne 1) { throw "Expected SCHED_TASK_COUNT=1. got $schedTaskCount" }
if ($task0Id -ne 1) { throw "Expected TASK0_ID=1. got $task0Id" }
if ($task0Priority -ne 2) { throw "Expected TASK0_PRIORITY=2. got $task0Priority" }
if ($task0Budget -ne 9) { throw "Expected TASK0_BUDGET=9. got $task0Budget" }

Write-Output 'BAREMETAL_QEMU_TIMER_WAKE_BASELINE_PROBE=pass'
Write-Output "ARTIFACT=$($artifactMatch.Groups[1].Value)"
Write-Output "TICKS=$ticks"
Write-Output "SCHED_TASK_COUNT=$schedTaskCount"
Write-Output "TASK0_ID=$task0Id"
Write-Output "TASK0_PRIORITY=$task0Priority"
Write-Output "TASK0_BUDGET=$task0Budget"
