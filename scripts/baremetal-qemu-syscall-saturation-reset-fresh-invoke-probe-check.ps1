# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 45,
    [int] $GdbPort = 0
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot 'baremetal-qemu-syscall-saturation-reset-probe-check.ps1'
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
    -SkippedPattern '(?m)^BAREMETAL_QEMU_SYSCALL_SATURATION_RESET_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_SYSCALL_SATURATION_RESET_FRESH_INVOKE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_SYSCALL_SATURATION_RESET_FRESH_INVOKE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-syscall-saturation-reset-probe-check.ps1' `
    -FailureLabel 'Syscall saturation-reset' `
    -EchoOnSuccess:$false `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true `
    -TrimEchoText:$true `
    -EmitSkippedSourceReceipt:$true `
    -InvokeArgs $invoke
$text = $probeState.Text
$outputText = $probeState.Text

$expected = @{
    'FRESH_ID' = 777
    'FRESH_TOKEN' = 53261
    'FRESH_INVOKE_COUNT' = 1
    'FRESH_LAST_ARG' = 153
    'FRESH_LAST_RESULT' = 54173
    'SECOND_SLOT_STATE' = 0
    'DISPATCH_COUNT' = 1
    'LAST_ID' = 777
    'STATE_LAST_RESULT' = 54173
}
foreach ($entry in $expected.GetEnumerator()) {
    $actual = Extract-IntValue -Text $text -Name $entry.Key
    if ($null -eq $actual) { throw "Missing output value for $($entry.Key)" }
    if ($actual -ne $entry.Value) { throw "Unexpected $($entry.Key): got $actual expected $($entry.Value)" }
}
$invokeTick = Extract-IntValue -Text $text -Name 'INVOKE_TICK'
if ($null -eq $invokeTick -or $invokeTick -le 0) { throw "Expected INVOKE_TICK > 0. got $invokeTick" }

Write-Output 'BAREMETAL_QEMU_SYSCALL_SATURATION_RESET_FRESH_INVOKE_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_SYSCALL_SATURATION_RESET_FRESH_INVOKE_PROBE_SOURCE=baremetal-qemu-syscall-saturation-reset-probe-check.ps1'
Write-Output 'FRESH_ID=777'
Write-Output 'FRESH_TOKEN=53261'
Write-Output 'FRESH_INVOKE_COUNT=1'
Write-Output 'FRESH_LAST_ARG=153'
Write-Output 'FRESH_LAST_RESULT=54173'
Write-Output 'SECOND_SLOT_STATE=0'
Write-Output 'DISPATCH_COUNT=1'
Write-Output 'LAST_ID=777'
Write-Output 'STATE_LAST_RESULT=54173'
Write-Output "INVOKE_TICK=$invokeTick"
