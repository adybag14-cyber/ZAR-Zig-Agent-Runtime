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
    -SkippedReceipt 'BAREMETAL_QEMU_SYSCALL_SATURATION_OVERFLOW_PRESERVE_FULL_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_SYSCALL_SATURATION_OVERFLOW_PRESERVE_FULL_PROBE_SOURCE' `
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

$entryCapacity = Extract-IntValue -Text $outputText -Name 'ENTRY_CAPACITY'
$entryCount = Extract-IntValue -Text $outputText -Name 'ENTRY_COUNT'
$fullCount = Extract-IntValue -Text $outputText -Name 'FULL_COUNT'
$lastRegisteredId = Extract-IntValue -Text $outputText -Name 'LAST_REGISTERED_ID'
$overflowResult = Extract-IntValue -Text $outputText -Name 'OVERFLOW_RESULT'

if ($entryCapacity -ne 64) { throw "Expected ENTRY_CAPACITY=64. got $entryCapacity" }
if ($entryCount -ne 64) { throw "Expected final ENTRY_COUNT=64. got $entryCount" }
if ($fullCount -ne 64) { throw "Expected FULL_COUNT=64. got $fullCount" }
if ($lastRegisteredId -ne 64) { throw "Expected LAST_REGISTERED_ID=64 before overflow. got $lastRegisteredId" }
if ($overflowResult -ne -28) { throw "Expected OVERFLOW_RESULT=-28. got $overflowResult" }

Write-Output 'BAREMETAL_QEMU_SYSCALL_SATURATION_OVERFLOW_PRESERVE_FULL_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_SYSCALL_SATURATION_OVERFLOW_PRESERVE_FULL_PROBE_SOURCE=baremetal-qemu-syscall-saturation-probe-check.ps1'
Write-Output "ENTRY_CAPACITY=$entryCapacity"
Write-Output "ENTRY_COUNT=$entryCount"
Write-Output "FULL_COUNT=$fullCount"
Write-Output "LAST_REGISTERED_ID=$lastRegisteredId"
Write-Output "OVERFLOW_RESULT=$overflowResult"
