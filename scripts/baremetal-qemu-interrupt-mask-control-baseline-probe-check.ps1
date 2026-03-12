param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-interrupt-mask-control-probe-check.ps1"

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $match = [regex]::Match($Text, '(?m)^' + [regex]::Escape($Name) + '=(-?\d+)\r?$')
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$probeOutput = if ($SkipBuild) { & $probe -SkipBuild 2>&1 } else { & $probe 2>&1 }
$probeExitCode = $LASTEXITCODE
$probeText = ($probeOutput | Out-String)
$probeOutput | Write-Output
if ($probeText -match '(?m)^BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE=skipped\r?$') {
    Write-Output 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_BASELINE_PROBE=skipped'
    Write-Output 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_BASELINE_PROBE_SOURCE=baremetal-qemu-interrupt-mask-control-probe-check.ps1'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying interrupt-mask-control probe failed with exit code $probeExitCode"
}

$task0State = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_SET_MASKED_TASK0_STATE'
$wakeQueueCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_SET_MASKED_WAKE_QUEUE_COUNT'
$ignoredCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_SET_MASKED_IGNORED_COUNT'
$profile = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_SET_MASKED_PROFILE'
$maskedCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_SET_MASKED_MASKED_COUNT'
$ack = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_ACK'
$lastOpcode = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_LAST_OPCODE'
$lastResult = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_LAST_RESULT'
if ($null -in @($task0State, $wakeQueueCount, $ignoredCount, $profile, $maskedCount, $ack, $lastOpcode, $lastResult)) {
    throw 'Missing baseline fields in interrupt-mask-control probe output.'
}
if ($task0State -ne 6) { throw "Expected SET_MASKED_TASK0_STATE=6, got $task0State" }
if ($wakeQueueCount -ne 0) { throw "Expected SET_MASKED_WAKE_QUEUE_COUNT=0, got $wakeQueueCount" }
if ($ignoredCount -ne 1) { throw "Expected SET_MASKED_IGNORED_COUNT=1, got $ignoredCount" }
if ($profile -ne 255) { throw "Expected SET_MASKED_PROFILE=255, got $profile" }
if ($maskedCount -ne 1) { throw "Expected SET_MASKED_MASKED_COUNT=1, got $maskedCount" }
if ($ack -ne 17) { throw "Expected ACK=17, got $ack" }
if ($lastOpcode -ne 64) { throw "Expected LAST_OPCODE=64, got $lastOpcode" }
if ($lastResult -ne 0) { throw "Expected LAST_RESULT=0, got $lastResult" }

Write-Output 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_BASELINE_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_BASELINE_PROBE_SOURCE=baremetal-qemu-interrupt-mask-control-probe-check.ps1'
Write-Output "SET_MASKED_TASK0_STATE=$task0State"
Write-Output "SET_MASKED_WAKE_QUEUE_COUNT=$wakeQueueCount"
Write-Output "SET_MASKED_IGNORED_COUNT=$ignoredCount"
Write-Output "SET_MASKED_PROFILE=$profile"
Write-Output "SET_MASKED_MASKED_COUNT=$maskedCount"
Write-Output "ACK=$ack"
Write-Output "LAST_OPCODE=$lastOpcode"
Write-Output "LAST_RESULT=$lastResult"
