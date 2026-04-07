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
    -SkippedReceipt 'BAREMETAL_QEMU_SYSCALL_CONTROL_UNREGISTER_CLEANUP_STAGE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_SYSCALL_CONTROL_UNREGISTER_CLEANUP_STAGE_PROBE_SOURCE' `
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

$unregisterResult = Extract-IntValue -Text $outputText -Name 'UNREGISTER_RESULT'
$unregisterEntryCount = Extract-IntValue -Text $outputText -Name 'UNREGISTER_ENTRY_COUNT'
$unregisterEntryState = Extract-IntValue -Text $outputText -Name 'UNREGISTER_ENTRY_STATE'
$missingFlagsResult = Extract-IntValue -Text $outputText -Name 'MISSING_FLAGS_RESULT'
$missingUnregisterResult = Extract-IntValue -Text $outputText -Name 'MISSING_UNREGISTER_RESULT'

if ($unregisterResult -ne 0) { throw "Expected UNREGISTER_RESULT=0. got $unregisterResult" }
if ($unregisterEntryCount -ne 0) { throw "Expected UNREGISTER_ENTRY_COUNT=0. got $unregisterEntryCount" }
if ($unregisterEntryState -ne 0) { throw "Expected UNREGISTER_ENTRY_STATE=0. got $unregisterEntryState" }
if ($missingFlagsResult -ne -2) { throw "Expected MISSING_FLAGS_RESULT=-2. got $missingFlagsResult" }
if ($missingUnregisterResult -ne -2) { throw "Expected MISSING_UNREGISTER_RESULT=-2. got $missingUnregisterResult" }

Write-Output 'BAREMETAL_QEMU_SYSCALL_CONTROL_UNREGISTER_CLEANUP_STAGE_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_SYSCALL_CONTROL_UNREGISTER_CLEANUP_STAGE_PROBE_SOURCE=baremetal-qemu-syscall-control-probe-check.ps1'
Write-Output "UNREGISTER_RESULT=$unregisterResult"
Write-Output "UNREGISTER_ENTRY_COUNT=$unregisterEntryCount"
Write-Output "UNREGISTER_ENTRY_STATE=$unregisterEntryState"
Write-Output "MISSING_FLAGS_RESULT=$missingFlagsResult"
Write-Output "MISSING_UNREGISTER_RESULT=$missingUnregisterResult"
