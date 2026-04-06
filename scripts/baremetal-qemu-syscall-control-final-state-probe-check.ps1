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
    -SkippedReceipt 'BAREMETAL_QEMU_SYSCALL_CONTROL_FINAL_STATE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_SYSCALL_CONTROL_FINAL_STATE_PROBE_SOURCE' `
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

$missingFlagsResult = Extract-IntValue -Text $outputText -Name 'MISSING_FLAGS_RESULT'
$entryCount = Extract-IntValue -Text $outputText -Name 'ENTRY_COUNT'
$entry0State = Extract-IntValue -Text $outputText -Name 'ENTRY0_STATE'
$entry0Flags = Extract-IntValue -Text $outputText -Name 'ENTRY0_FLAGS'
$entry0InvokeCount = Extract-IntValue -Text $outputText -Name 'ENTRY0_INVOKE_COUNT'
$enabled = Extract-IntValue -Text $outputText -Name 'ENABLED'

if ($missingFlagsResult -ne -2) { throw "Expected MISSING_FLAGS_RESULT=-2. got $missingFlagsResult" }
if ($entryCount -ne 0) { throw "Expected final ENTRY_COUNT=0 after unregister cleanup. got $entryCount" }
if ($entry0State -ne 0) { throw "Expected ENTRY0_STATE=0 after unregister cleanup. got $entry0State" }
if ($entry0Flags -ne 0) { throw "Expected ENTRY0_FLAGS=0 after unregister cleanup. got $entry0Flags" }
if ($entry0InvokeCount -ne 0) { throw "Expected ENTRY0_INVOKE_COUNT=0 after unregister cleanup. got $entry0InvokeCount" }
if ($enabled -ne 1) { throw "Expected final ENABLED=1. got $enabled" }

Write-Output 'BAREMETAL_QEMU_SYSCALL_CONTROL_FINAL_STATE_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_SYSCALL_CONTROL_FINAL_STATE_PROBE_SOURCE=baremetal-qemu-syscall-control-probe-check.ps1'
Write-Output "MISSING_FLAGS_RESULT=$missingFlagsResult"
Write-Output "ENTRY_COUNT=$entryCount"
Write-Output "ENTRY0_STATE=$entry0State"
Write-Output "ENTRY0_FLAGS=$entry0Flags"
Write-Output "ENTRY0_INVOKE_COUNT=$entry0InvokeCount"
Write-Output "ENABLED=$enabled"
