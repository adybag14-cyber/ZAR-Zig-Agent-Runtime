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
    -SkippedReceipt 'BAREMETAL_QEMU_SYSCALL_CONTROL_REREGISTER_STAGE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_SYSCALL_CONTROL_REREGISTER_STAGE_PROBE_SOURCE' `
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

$updatedToken = Extract-IntValue -Text $outputText -Name 'UPDATED_TOKEN'
$reregisterEntryCount = Extract-IntValue -Text $outputText -Name 'REREGISTER_ENTRY_COUNT'
$reregisterInvokeCount = Extract-IntValue -Text $outputText -Name 'REREGISTER_INVOKE_COUNT'

if ($updatedToken -ne 51966) { throw "Expected UPDATED_TOKEN=51966. got $updatedToken" }
if ($reregisterEntryCount -ne 1) { throw "Expected REREGISTER_ENTRY_COUNT=1. got $reregisterEntryCount" }
if ($reregisterInvokeCount -ne 0) { throw "Expected REREGISTER_INVOKE_COUNT=0. got $reregisterInvokeCount" }

Write-Output 'BAREMETAL_QEMU_SYSCALL_CONTROL_REREGISTER_STAGE_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_SYSCALL_CONTROL_REREGISTER_STAGE_PROBE_SOURCE=baremetal-qemu-syscall-control-probe-check.ps1'
Write-Output "UPDATED_TOKEN=$updatedToken"
Write-Output "REREGISTER_ENTRY_COUNT=$reregisterEntryCount"
Write-Output "REREGISTER_INVOKE_COUNT=$reregisterInvokeCount"
