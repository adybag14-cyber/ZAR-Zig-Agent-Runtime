# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 90
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'baremetal-qemu-wrapper-common.ps1')
$probe = Join-Path $PSScriptRoot 'baremetal-qemu-bootdiag-history-clear-probe-check.ps1'
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$invoke = @{ TimeoutSeconds = $TimeoutSeconds }
$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_BOOTDIAG_HISTORY_CLEAR_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_BOOTDIAG_HISTORY_CLEAR_BASELINE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_BOOTDIAG_HISTORY_CLEAR_BASELINE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-bootdiag-history-clear-probe-check.ps1' `
    -FailureLabel 'Bootdiag/history-clear' `
    -EchoOnSuccess:$false `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true `
    -TrimEchoText:$true `
    -EmitSkippedSourceReceipt:$true `
    -InvokeArgs $invoke
$outputText = $probeState.Text

foreach ($name in @(
    'BAREMETAL_QEMU_BOOTDIAG_HISTORY_CLEAR_PROBE',
    'BAREMETAL_QEMU_BOOTDIAG_HISTORY_CLEAR_PROBE_SOURCE'
)) {
    if ($outputText -notmatch ('(?m)^' + [regex]::Escape($name) + '=(.+)\r?$')) {
        throw "Missing expected output '$name'"
    }
}

Write-Output 'BAREMETAL_QEMU_BOOTDIAG_HISTORY_CLEAR_BASELINE_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_BOOTDIAG_HISTORY_CLEAR_BASELINE_PROBE_SOURCE=baremetal-qemu-bootdiag-history-clear-probe-check.ps1'
