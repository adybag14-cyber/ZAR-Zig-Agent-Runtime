# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 45,
    [int] $GdbPort = 0
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-syscall-saturation-probe-check.ps1"
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
    -SkippedPattern '(?m)^BAREMETAL_QEMU_SYSCALL_SATURATION_PROBE=skipped\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_SYSCALL_SATURATION_REUSE_SLOT_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_SYSCALL_SATURATION_REUSE_SLOT_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-syscall-saturation-probe-check.ps1' `
    -FailureLabel 'Syscall saturation' `
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

$reusePreviousId = Extract-IntValue -Text $outputText -Name 'REUSE_PREVIOUS_ID'
$reuseNewId = Extract-IntValue -Text $outputText -Name 'REUSE_NEW_ID'
$reuseToken = Extract-IntValue -Text $outputText -Name 'REUSE_TOKEN'
$reuseInvokeCount = Extract-IntValue -Text $outputText -Name 'REUSE_INVOKE_COUNT'
$reuseLastArg = Extract-IntValue -Text $outputText -Name 'REUSE_LAST_ARG'
$reuseLastResult = Extract-IntValue -Text $outputText -Name 'REUSE_LAST_RESULT'

if ($reusePreviousId -ne 6) { throw "Expected REUSE_PREVIOUS_ID=6. got $reusePreviousId" }
if ($reuseNewId -ne 106) { throw "Expected REUSE_NEW_ID=106. got $reuseNewId" }
if ($reuseToken -ne 42330) { throw "Expected REUSE_TOKEN=42330. got $reuseToken" }
if ($reuseInvokeCount -ne 1) { throw "Expected REUSE_INVOKE_COUNT=1. got $reuseInvokeCount" }
if ($reuseLastArg -ne 102) { throw "Expected REUSE_LAST_ARG=102. got $reuseLastArg" }
if ($reuseLastResult -ne 42326) { throw "Expected REUSE_LAST_RESULT=42326. got $reuseLastResult" }

Write-Output 'BAREMETAL_QEMU_SYSCALL_SATURATION_REUSE_SLOT_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_SYSCALL_SATURATION_REUSE_SLOT_PROBE_SOURCE=baremetal-qemu-syscall-saturation-probe-check.ps1'
Write-Output "REUSE_PREVIOUS_ID=$reusePreviousId"
Write-Output "REUSE_NEW_ID=$reuseNewId"
Write-Output "REUSE_TOKEN=$reuseToken"
Write-Output "REUSE_INVOKE_COUNT=$reuseInvokeCount"
Write-Output "REUSE_LAST_ARG=$reuseLastArg"
Write-Output "REUSE_LAST_RESULT=$reuseLastResult"
