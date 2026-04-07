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
    -SkippedReceipt 'BAREMETAL_QEMU_SYSCALL_CONTROL_BASELINE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_SYSCALL_CONTROL_BASELINE_PROBE_SOURCE' `
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

$expected = @{
    'ACK' = 13
    'LAST_OPCODE' = 35
    'LAST_RESULT' = -2
    'STATUS_MODE' = 1
}
foreach ($entry in $expected.GetEnumerator()) {
    $actual = Extract-IntValue -Text $text -Name $entry.Key
    if ($null -eq $actual) { throw "Missing output value for $($entry.Key)" }
    if ($actual -ne $entry.Value) { throw "Unexpected $($entry.Key): got $actual expected $($entry.Value)" }
}

Write-Output 'BAREMETAL_QEMU_SYSCALL_CONTROL_BASELINE_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_SYSCALL_CONTROL_BASELINE_PROBE_SOURCE=baremetal-qemu-syscall-control-probe-check.ps1'
Write-Output 'ACK=13'
Write-Output 'LAST_OPCODE=35'
Write-Output 'LAST_RESULT=-2'
Write-Output 'STATUS_MODE=1'
