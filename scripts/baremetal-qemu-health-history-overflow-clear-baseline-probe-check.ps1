# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 90
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'baremetal-qemu-wrapper-common.ps1')
$probe = Join-Path $PSScriptRoot 'baremetal-qemu-health-history-overflow-clear-probe-check.ps1'
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$invoke = @{ TimeoutSeconds = $TimeoutSeconds }
$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_HEALTH_HISTORY_OVERFLOW_CLEAR_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_HEALTH_HISTORY_OVERFLOW_CLEAR_BASELINE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_HEALTH_HISTORY_OVERFLOW_CLEAR_BASELINE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-health-history-overflow-clear-probe-check.ps1' `
    -FailureLabel 'Health-history overflow/clear' `
    -EchoOnSuccess:$false `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true `
    -TrimEchoText:$true `
    -EmitSkippedSourceReceipt:$true `
    -InvokeArgs $invoke
$outputText = $probeState.Text

if ($outputText -notmatch '(?m)^BAREMETAL_QEMU_HEALTH_HISTORY_OVERFLOW_CLEAR_PROBE=pass\r?$') {
    throw 'Broad health-history overflow/clear probe did not report pass'
}
if ($outputText -notmatch '(?m)^BAREMETAL_QEMU_HEALTH_HISTORY_OVERFLOW_CLEAR_PROBE_SOURCE=baremetal-qemu-command-health-history-probe-check\.ps1,baremetal-qemu-bootdiag-history-clear-probe-check\.ps1\r?$') {
    throw 'Unexpected broad probe source metadata for health-history overflow/clear baseline wrapper'
}

Write-Output 'BAREMETAL_QEMU_HEALTH_HISTORY_OVERFLOW_CLEAR_BASELINE_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_HEALTH_HISTORY_OVERFLOW_CLEAR_BASELINE_PROBE_SOURCE=baremetal-qemu-health-history-overflow-clear-probe-check.ps1'
