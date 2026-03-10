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

$terminateLastResult = Get-Int "BAREMETAL_QEMU_SCHEDULER_SATURATION_TERMINATE_LAST_RESULT"
$terminateTaskCount = Get-Int "BAREMETAL_QEMU_SCHEDULER_SATURATION_TERMINATE_TASK_COUNT"
$terminatedState = Get-Int "BAREMETAL_QEMU_SCHEDULER_SATURATION_TERMINATED_STATE"

if ($terminateLastResult -ne 0) { throw "Expected TERMINATE_LAST_RESULT=0, got $terminateLastResult" }
if ($terminateTaskCount -ne 15) { throw "Expected TERMINATE_TASK_COUNT=15, got $terminateTaskCount" }
if ($terminatedState -ne 4) { throw "Expected TERMINATED_STATE=4, got $terminatedState" }

Write-Output "BAREMETAL_QEMU_SCHEDULER_SATURATION_TERMINATE_STATE_PROBE=pass"
Write-Output "TERMINATE_LAST_RESULT=$terminateLastResult"
Write-Output "TERMINATE_TASK_COUNT=$terminateTaskCount"
Write-Output "TERMINATED_STATE=$terminatedState"
