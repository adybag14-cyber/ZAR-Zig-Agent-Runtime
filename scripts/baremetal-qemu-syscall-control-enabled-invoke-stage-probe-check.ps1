# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 45,
    [int] $GdbPort = 1287
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot 'baremetal-qemu-syscall-control-probe-check.ps1'
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $match = [regex]::Match($Text, '(?m)^' + [regex]::Escape($Name) + '=(-?\d+)\r?$')
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$invoke = @{ TimeoutSeconds = $TimeoutSeconds; GdbPort = $GdbPort }
if ($SkipBuild) { $invoke.SkipBuild = $true }

$output = & $probe @invoke 2>&1
$exitCode = $LASTEXITCODE
$outputText = ($output | Out-String)
if ($outputText -match '(?m)^BAREMETAL_QEMU_SYSCALL_CONTROL_PROBE=skipped\r?$') {
    if ($outputText) { Write-Output $outputText.TrimEnd() }
    Write-Output 'BAREMETAL_QEMU_SYSCALL_CONTROL_ENABLED_INVOKE_STAGE_PROBE=skipped'
    Write-Output 'BAREMETAL_QEMU_SYSCALL_CONTROL_ENABLED_INVOKE_STAGE_PROBE_SOURCE=baremetal-qemu-syscall-control-probe-check.ps1'
    exit 0
}
if ($exitCode -ne 0) {
    if ($outputText) { Write-Output $outputText.TrimEnd() }
    throw "Syscall control prerequisite probe failed with exit code $exitCode"
}

$invokeResult = Extract-IntValue -Text $outputText -Name 'INVOKE_RESULT'
$invokeTick = Extract-IntValue -Text $outputText -Name 'INVOKE_TICK'
$invokeEntryCount = Extract-IntValue -Text $outputText -Name 'INVOKE_ENTRY_COUNT'
$invokeEntryInvokeCount = Extract-IntValue -Text $outputText -Name 'INVOKE_ENTRY_INVOKE_COUNT'
$invokeEntryLastArg = Extract-IntValue -Text $outputText -Name 'INVOKE_ENTRY_LAST_ARG'
$invokeEntryLastResult = Extract-IntValue -Text $outputText -Name 'INVOKE_ENTRY_LAST_RESULT'

if ($invokeResult -ne 55489) { throw "Expected INVOKE_RESULT=55489. got $invokeResult" }
if ($invokeTick -le 0) { throw "Expected INVOKE_TICK>0. got $invokeTick" }
if ($invokeEntryCount -ne 1) { throw "Expected INVOKE_ENTRY_COUNT=1. got $invokeEntryCount" }
if ($invokeEntryInvokeCount -ne 1) { throw "Expected INVOKE_ENTRY_INVOKE_COUNT=1. got $invokeEntryInvokeCount" }
if ($invokeEntryLastArg -ne 4660) { throw "Expected INVOKE_ENTRY_LAST_ARG=4660. got $invokeEntryLastArg" }
if ($invokeEntryLastResult -ne 55489) { throw "Expected INVOKE_ENTRY_LAST_RESULT=55489. got $invokeEntryLastResult" }

Write-Output 'BAREMETAL_QEMU_SYSCALL_CONTROL_ENABLED_INVOKE_STAGE_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_SYSCALL_CONTROL_ENABLED_INVOKE_STAGE_PROBE_SOURCE=baremetal-qemu-syscall-control-probe-check.ps1'
Write-Output "INVOKE_RESULT=$invokeResult"
Write-Output "INVOKE_TICK=$invokeTick"
Write-Output "INVOKE_ENTRY_COUNT=$invokeEntryCount"
Write-Output "INVOKE_ENTRY_INVOKE_COUNT=$invokeEntryInvokeCount"
Write-Output "INVOKE_ENTRY_LAST_ARG=$invokeEntryLastArg"
Write-Output "INVOKE_ENTRY_LAST_RESULT=$invokeEntryLastResult"
