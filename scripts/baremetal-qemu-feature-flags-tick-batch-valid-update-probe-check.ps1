# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 30,
    [int] $GdbPort = 0
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-feature-flags-tick-batch-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$invoke = @{ TimeoutSeconds = $TimeoutSeconds; GdbPort = $GdbPort }
$probeState = Invoke-WrapperProbe -ProbePath $probe -SkipBuild:$SkipBuild -SkippedPattern '(?m)^BAREMETAL_QEMU_FEATURE_FLAGS_TICK_BATCH_PROBE=skipped\r?$' -SkippedReceipt 'BAREMETAL_QEMU_FEATURE_FLAGS_TICK_BATCH_VALID_UPDATE_PROBE' -SkippedSourceReceipt 'BAREMETAL_QEMU_FEATURE_FLAGS_TICK_BATCH_VALID_UPDATE_PROBE_SOURCE' -SkippedSourceValue 'baremetal-qemu-feature-flags-tick-batch-probe-check.ps1' -FailureLabel 'feature-flags/tick-batch' -InvokeArgs $invoke
$probeText = $probeState.Text
$expected = @{
    'BAREMETAL_QEMU_FEATURE_FLAGS_TICK_BATCH_STAGE2_ACK' = 2
    'BAREMETAL_QEMU_FEATURE_FLAGS_TICK_BATCH_STAGE2_LAST_OPCODE' = 6
    'BAREMETAL_QEMU_FEATURE_FLAGS_TICK_BATCH_STAGE2_LAST_RESULT' = 0
    'BAREMETAL_QEMU_FEATURE_FLAGS_TICK_BATCH_STAGE2_TICKS' = 5
    'BAREMETAL_QEMU_FEATURE_FLAGS_TICK_BATCH_STAGE2_FEATURE_FLAGS' = 2774181210
    'BAREMETAL_QEMU_FEATURE_FLAGS_TICK_BATCH_STAGE2_TICK_BATCH_HINT' = 4
}

foreach ($entry in $expected.GetEnumerator()) {
    $actual = Extract-IntValue -Text $probeText -Name $entry.Key
    if ($null -eq $actual) { throw "Missing output value for $($entry.Key)" }
    if ($actual -ne $entry.Value) { throw "Unexpected $($entry.Key): got $actual expected $($entry.Value)" }
}

Write-Output 'BAREMETAL_QEMU_FEATURE_FLAGS_TICK_BATCH_VALID_UPDATE_PROBE=pass'
Write-Output 'STAGE2_ACK=2'
Write-Output 'STAGE2_LAST_OPCODE=6'
Write-Output 'STAGE2_LAST_RESULT=0'
Write-Output 'STAGE2_TICKS=5'
Write-Output 'STAGE2_FEATURE_FLAGS=2774181210'
Write-Output 'STAGE2_TICK_BATCH_HINT=4'
