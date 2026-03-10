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

$overflowResult = Get-Int "BAREMETAL_QEMU_SCHEDULER_SATURATION_OVERFLOW_RESULT"
$overflowTaskCount = Get-Int "BAREMETAL_QEMU_SCHEDULER_SATURATION_OVERFLOW_TASK_COUNT"
$previousId = Get-Int "BAREMETAL_QEMU_SCHEDULER_SATURATION_REUSED_SLOT_PREVIOUS_ID"

if ($overflowResult -ne -28) { throw "Expected OVERFLOW_RESULT=-28, got $overflowResult" }
if ($overflowTaskCount -ne 16) { throw "Expected OVERFLOW_TASK_COUNT=16, got $overflowTaskCount" }
if ($previousId -le 0) { throw "Expected REUSED_SLOT_PREVIOUS_ID > 0, got $previousId" }

Write-Output "BAREMETAL_QEMU_SCHEDULER_SATURATION_OVERFLOW_PRESERVE_PROBE=pass"
Write-Output "OVERFLOW_RESULT=$overflowResult"
Write-Output "OVERFLOW_TASK_COUNT=$overflowTaskCount"
Write-Output "REUSED_SLOT_PREVIOUS_ID=$previousId"
