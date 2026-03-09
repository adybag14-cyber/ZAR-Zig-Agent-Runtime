param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-timer-reset-recovery-probe-check.ps1"

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
if ($probeText -match 'BAREMETAL_QEMU_TIMER_RESET_RECOVERY_PROBE=skipped') {
    Write-Output "BAREMETAL_QEMU_TIMER_RESET_TIMEOUT_INTERRUPT_RECOVERY_PROBE=skipped"
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying timer-reset-recovery probe failed with exit code $probeExitCode"
}

$task1Id = Extract-IntValue -Text $probeText -Name 'TASK1_ID'
$postWaitKind1 = Extract-IntValue -Text $probeText -Name 'POST_WAIT_KIND1'
$postWaitTimeout1 = Extract-IntValue -Text $probeText -Name 'POST_WAIT_TIMEOUT1'
$afterInterruptWakeCount = Extract-IntValue -Text $probeText -Name 'AFTER_INTERRUPT_WAKE_COUNT'
$wake1TaskId = Extract-IntValue -Text $probeText -Name 'WAKE1_TASK_ID'
$wake1TimerId = Extract-IntValue -Text $probeText -Name 'WAKE1_TIMER_ID'
$wake1Reason = Extract-IntValue -Text $probeText -Name 'WAKE1_REASON'
$wake1Vector = Extract-IntValue -Text $probeText -Name 'WAKE1_VECTOR'

if ($null -in @($task1Id, $postWaitKind1, $postWaitTimeout1, $afterInterruptWakeCount, $wake1TaskId, $wake1TimerId, $wake1Reason, $wake1Vector)) {
    throw 'Missing expected timer-reset timeout-interrupt recovery fields in probe output.'
}
if ($postWaitKind1 -ne 3) {
    throw "Expected timeout-backed interrupt wait to preserve interrupt-any wait-kind=3 across timer reset. got $postWaitKind1"
}
if ($postWaitTimeout1 -ne 0) {
    throw "Expected timeout-backed interrupt wait timeout arm to be cleared by timer reset. got $postWaitTimeout1"
}
if ($afterInterruptWakeCount -ne 2) {
    throw "Expected interrupt recovery to append the second wake after manual recovery. got $afterInterruptWakeCount"
}
if ($wake1TaskId -ne $task1Id) {
    throw "Expected interrupt recovery wake to target task1=$task1Id. got $wake1TaskId"
}
if ($wake1TimerId -ne 0) {
    throw "Expected interrupt recovery wake to have timer_id=0. got $wake1TimerId"
}
if ($wake1Reason -ne 2) {
    throw "Expected interrupt recovery wake reason=2. got $wake1Reason"
}
if ($wake1Vector -le 0) {
    throw "Expected interrupt recovery wake to preserve a real interrupt vector. got $wake1Vector"
}

Write-Output 'BAREMETAL_QEMU_TIMER_RESET_TIMEOUT_INTERRUPT_RECOVERY_PROBE=pass'
Write-Output "TASK1_ID=$task1Id"
Write-Output "POST_WAIT_KIND1=$postWaitKind1"
Write-Output "POST_WAIT_TIMEOUT1=$postWaitTimeout1"
Write-Output "AFTER_INTERRUPT_WAKE_COUNT=$afterInterruptWakeCount"
Write-Output "WAKE1_TASK_ID=$wake1TaskId"
Write-Output "WAKE1_TIMER_ID=$wake1TimerId"
Write-Output "WAKE1_REASON=$wake1Reason"
Write-Output "WAKE1_VECTOR=$wake1Vector"
