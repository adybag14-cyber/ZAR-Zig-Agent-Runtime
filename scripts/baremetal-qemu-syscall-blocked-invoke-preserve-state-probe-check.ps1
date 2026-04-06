# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 40,
    [int] $GdbPort = 1287
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-syscall-control-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $match = [regex]::Match($Text, '(?m)^' + [regex]::Escape($Name) + '=(-?\d+)\r?$')
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$invoke = @{ TimeoutSeconds = $TimeoutSeconds; GdbPort = $GdbPort }
$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_SYSCALL_CONTROL_PROBE=skipped\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_SYSCALL_BLOCKED_INVOKE_PRESERVE_STATE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_SYSCALL_BLOCKED_INVOKE_PRESERVE_STATE_PROBE_SOURCE' `
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
function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $match = [regex]::Match($Text, '(?m)^' + [regex]::Escape($Name) + '=(-?\d+)\r?$')
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$blockedResult = Extract-IntValue -Text $outputText -Name 'BLOCKED_RESULT'
$dispatchCount = Extract-IntValue -Text $outputText -Name 'DISPATCH_COUNT'
$lastId = Extract-IntValue -Text $outputText -Name 'LAST_ID'
$entryCount = Extract-IntValue -Text $outputText -Name 'ENTRY_COUNT'

if ($blockedResult -ne -17) { throw "Expected BLOCKED_RESULT=-17. got $blockedResult" }
if ($dispatchCount -ne 1) { throw "Expected final DISPATCH_COUNT=1 after the later successful invoke only. got $dispatchCount" }
if ($lastId -ne 11) { throw "Expected LAST_ID=11 from the later successful invoke. got $lastId" }
if ($entryCount -ne 0) { throw "Expected final ENTRY_COUNT=0 after unregister cleanup. got $entryCount" }

Write-Output 'BAREMETAL_QEMU_SYSCALL_BLOCKED_INVOKE_PRESERVE_STATE_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_SYSCALL_BLOCKED_INVOKE_PRESERVE_STATE_PROBE_SOURCE=baremetal-qemu-syscall-control-probe-check.ps1'
Write-Output "BLOCKED_RESULT=$blockedResult"
Write-Output "DISPATCH_COUNT=$dispatchCount"
Write-Output "LAST_ID=$lastId"
Write-Output "ENTRY_COUNT=$entryCount"
