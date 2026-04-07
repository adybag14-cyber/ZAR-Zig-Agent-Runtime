# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-command-health-history-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe -ProbePath $probe -SkipBuild:$SkipBuild -SkippedPattern '(?m)^BAREMETAL_QEMU_COMMAND_HEALTH_HISTORY_PROBE=skipped\r?$' -SkippedReceipt 'BAREMETAL_QEMU_COMMAND_HEALTH_HISTORY_COMMAND_SHAPE_PROBE' -SkippedSourceReceipt 'BAREMETAL_QEMU_COMMAND_HEALTH_HISTORY_COMMAND_SHAPE_PROBE_SOURCE' -SkippedSourceValue 'baremetal-qemu-command-health-history-probe-check.ps1' -FailureLabel 'command-health history'
$probeText = $probeState.Text
len = Extract-IntValue -Text $probeText -Name 'COMMAND_HISTORY_LEN'
$overflow = Extract-IntValue -Text $probeText -Name 'COMMAND_HISTORY_OVERFLOW'
$head = Extract-IntValue -Text $probeText -Name 'COMMAND_HISTORY_HEAD'

if ($null -in @($len, $overflow, $head)) {
    throw 'Missing command-history shape fields.'
}
if ($len -ne 32) { throw "Expected COMMAND_HISTORY_LEN=32. got $len" }
if ($overflow -ne 3) { throw "Expected COMMAND_HISTORY_OVERFLOW=3. got $overflow" }
if ($head -ne 3) { throw "Expected COMMAND_HISTORY_HEAD=3. got $head" }

Write-Output 'BAREMETAL_QEMU_COMMAND_HEALTH_HISTORY_COMMAND_SHAPE_PROBE=pass'
Write-Output "COMMAND_HISTORY_LEN=$len"
Write-Output "COMMAND_HISTORY_OVERFLOW=$overflow"
Write-Output "COMMAND_HISTORY_HEAD=$head"
