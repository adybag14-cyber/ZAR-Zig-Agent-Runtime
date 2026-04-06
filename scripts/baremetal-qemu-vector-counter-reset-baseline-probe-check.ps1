# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-vector-counter-reset-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_VECTOR_COUNTER_RESET_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_VECTOR_COUNTER_RESET_BASELINE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_VECTOR_COUNTER_RESET_BASELINE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-vector-counter-reset-probe-check.ps1' `
    -FailureLabel 'vector-counter-reset'
$probeText = $probeState.Text

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $pattern = '(?m)^' + [regex]::Escape($Name) + '=(.+)\\r?$'
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { return $null }
    return $match.Groups[1].Value.Trim()
}


$artifact = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_VECTOR_COUNTER_RESET_ARTIFACT'
$startAddr = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_VECTOR_COUNTER_RESET_START_ADDR'
$statusAddr = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_VECTOR_COUNTER_RESET_STATUS_ADDR'
$mailboxAddr = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_VECTOR_COUNTER_RESET_MAILBOX_ADDR'
$ticks = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_VECTOR_COUNTER_RESET_TICKS'

if ([string]::IsNullOrWhiteSpace($artifact) -or [string]::IsNullOrWhiteSpace($startAddr) -or [string]::IsNullOrWhiteSpace($statusAddr) -or [string]::IsNullOrWhiteSpace($mailboxAddr) -or [string]::IsNullOrWhiteSpace($ticks)) {
    throw 'Missing baseline vector-counter-reset receipt fields in probe output.'
}
if (-not ($startAddr -like '0x*') -or -not ($statusAddr -like '0x*') -or -not ($mailboxAddr -like '0x*')) {
    throw "Unexpected address encoding in vector-counter-reset baseline output. start=$startAddr status=$statusAddr mailbox=$mailboxAddr"
}
if ([int64]$ticks -lt 8) {
    throw "Expected TICKS>=8 in vector-counter-reset baseline output, got $ticks"
}

Write-Output 'BAREMETAL_QEMU_VECTOR_COUNTER_RESET_BASELINE_PROBE=pass'
Write-Output "ARTIFACT=$artifact"
Write-Output "START_ADDR=$startAddr"
Write-Output "STATUS_ADDR=$statusAddr"
Write-Output "MAILBOX_ADDR=$mailboxAddr"
Write-Output "TICKS=$ticks"
