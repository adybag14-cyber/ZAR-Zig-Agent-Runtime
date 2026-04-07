# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 45,
    [int] $GdbPort = 1287
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot 'baremetal-qemu-syscall-control-probe-check.ps1'
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $match = [regex]::Match($Text, '(?m)^' + [regex]::Escape($Name) + '=(-?\\d+)\\r?$')
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$invoke = @{ TimeoutSeconds = $TimeoutSeconds; GdbPort = $GdbPort }
$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_SYSCALL_CONTROL_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_SYSCALL_CONTROL_BLOCKED_STATE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_SYSCALL_CONTROL_BLOCKED_STATE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-syscall-control-probe-check.ps1' `
    -FailureLabel 'Syscall control' `
    -EchoOnSuccess:$false `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true `
    -TrimEchoText:$true `
    -EmitSkippedSourceReceipt:$true `
    -InvokeArgs $invoke
$text = $probeState.Text
$outputText = $probeState.Text

$blockedResult = Extract-IntValue -Text $outputText -Name 'BLOCKED_RESULT'
$blockedFlags = Extract-IntValue -Text $outputText -Name 'BLOCKED_FLAGS'
$blockedEntryCount = Extract-IntValue -Text $outputText -Name 'BLOCKED_ENTRY_COUNT'
$blockedDispatchCount = Extract-IntValue -Text $outputText -Name 'BLOCKED_DISPATCH_COUNT'

if ($blockedResult -ne -17) { throw "Expected BLOCKED_RESULT=-17. got $blockedResult" }
if ($blockedFlags -ne 1) { throw "Expected BLOCKED_FLAGS=1. got $blockedFlags" }
if ($blockedEntryCount -ne 1) { throw "Expected BLOCKED_ENTRY_COUNT=1. got $blockedEntryCount" }
if ($blockedDispatchCount -ne 0) { throw "Expected BLOCKED_DISPATCH_COUNT=0. got $blockedDispatchCount" }

Write-Output 'BAREMETAL_QEMU_SYSCALL_CONTROL_BLOCKED_STATE_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_SYSCALL_CONTROL_BLOCKED_STATE_PROBE_SOURCE=baremetal-qemu-syscall-control-probe-check.ps1'
Write-Output "BLOCKED_RESULT=$blockedResult"
Write-Output "BLOCKED_FLAGS=$blockedFlags"
Write-Output "BLOCKED_ENTRY_COUNT=$blockedEntryCount"
Write-Output "BLOCKED_DISPATCH_COUNT=$blockedDispatchCount"
