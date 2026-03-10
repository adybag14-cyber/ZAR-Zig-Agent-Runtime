param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-scheduler-saturation-probe-check.ps1"
$output = if ($SkipBuild) {
    & powershell -ExecutionPolicy Bypass -File $probe -SkipBuild | Out-String
} else {
    & powershell -ExecutionPolicy Bypass -File $probe | Out-String
}

function Get-Int([string] $name) {
    $match = [regex]::Match($output, '(?m)^' + [regex]::Escape($name) + '=(-?\d+)\r?$')
    if (-not $match.Success) { throw "Missing $name" }
    return [int64]::Parse($match.Groups[1].Value)
}

$ack = Get-Int "BAREMETAL_QEMU_SCHEDULER_SATURATION_ACK"
$lastOpcode = Get-Int "BAREMETAL_QEMU_SCHEDULER_SATURATION_LAST_OPCODE"
$lastResult = Get-Int "BAREMETAL_QEMU_SCHEDULER_SATURATION_LAST_RESULT"
$taskCount = Get-Int "BAREMETAL_QEMU_SCHEDULER_SATURATION_TASK_COUNT"
$reusedState = Get-Int "BAREMETAL_QEMU_SCHEDULER_SATURATION_REUSED_STATE"

if ($ack -ne 20) { throw "Expected ACK=20, got $ack" }
if ($lastOpcode -ne 27) { throw "Expected LAST_OPCODE=27, got $lastOpcode" }
if ($lastResult -ne 0) { throw "Expected LAST_RESULT=0, got $lastResult" }
if ($taskCount -ne 16) { throw "Expected TASK_COUNT=16, got $taskCount" }
if ($reusedState -ne 1) { throw "Expected REUSED_STATE=1, got $reusedState" }

Write-Output "BAREMETAL_QEMU_SCHEDULER_SATURATION_FINAL_STATE_PROBE=pass"
Write-Output "ACK=$ack"
Write-Output "LAST_OPCODE=$lastOpcode"
Write-Output "LAST_RESULT=$lastResult"
Write-Output "TASK_COUNT=$taskCount"
Write-Output "REUSED_STATE=$reusedState"
