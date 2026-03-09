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
    Write-Output "BAREMETAL_QEMU_TIMER_RESET_PURE_WAIT_RECOVERY_PROBE=skipped"
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying timer-reset-recovery probe failed with exit code $probeExitCode"
}

$task0Id = Extract-IntValue -Text $probeText -Name 'TASK0_ID'
$postWaitKind0 = Extract-IntValue -Text $probeText -Name 'POST_WAIT_KIND0'
$afterManualWakeCount = Extract-IntValue -Text $probeText -Name 'AFTER_MANUAL_WAKE_COUNT'
$wake0TaskId = Extract-IntValue -Text $probeText -Name 'WAKE0_TASK_ID'
$wake0TimerId = Extract-IntValue -Text $probeText -Name 'WAKE0_TIMER_ID'
$wake0Reason = Extract-IntValue -Text $probeText -Name 'WAKE0_REASON'
$wake0Vector = Extract-IntValue -Text $probeText -Name 'WAKE0_VECTOR'

if ($null -in @($task0Id, $postWaitKind0, $afterManualWakeCount, $wake0TaskId, $wake0TimerId, $wake0Reason, $wake0Vector)) {
    throw 'Missing expected timer-reset pure-wait recovery fields in probe output.'
}
if ($postWaitKind0 -ne 1) {
    throw "Expected pure timer wait to collapse to manual wait-kind=1 after timer reset. got $postWaitKind0"
}
if ($afterManualWakeCount -ne 1) {
    throw "Expected exactly one wake after manual recovery of the reset pure timer wait. got $afterManualWakeCount"
}
if ($wake0TaskId -ne $task0Id) {
    throw "Expected the recovered manual wake to target task0=$task0Id. got $wake0TaskId"
}
if ($wake0TimerId -ne 0) {
    throw "Expected recovered manual wake to have timer_id=0. got $wake0TimerId"
}
if ($wake0Reason -ne 3) {
    throw "Expected recovered pure timer wait to wake with manual reason=3. got $wake0Reason"
}
if ($wake0Vector -ne 0) {
    throw "Expected recovered manual wake vector=0. got $wake0Vector"
}

Write-Output 'BAREMETAL_QEMU_TIMER_RESET_PURE_WAIT_RECOVERY_PROBE=pass'
Write-Output "TASK0_ID=$task0Id"
Write-Output "POST_WAIT_KIND0=$postWaitKind0"
Write-Output "AFTER_MANUAL_WAKE_COUNT=$afterManualWakeCount"
Write-Output "WAKE0_TASK_ID=$wake0TaskId"
Write-Output "WAKE0_TIMER_ID=$wake0TimerId"
Write-Output "WAKE0_REASON=$wake0Reason"
Write-Output "WAKE0_VECTOR=$wake0Vector"
