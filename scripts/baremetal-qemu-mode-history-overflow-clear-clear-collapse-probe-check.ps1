# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 90
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'baremetal-qemu-wrapper-common.ps1')
$probe = Join-Path $PSScriptRoot 'baremetal-qemu-mode-history-overflow-clear-probe-check.ps1'
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$invoke = @{ TimeoutSeconds = $TimeoutSeconds }
$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_MODE_HISTORY_OVERFLOW_CLEAR_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_MODE_HISTORY_OVERFLOW_CLEAR_CLEAR_COLLAPSE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_MODE_HISTORY_OVERFLOW_CLEAR_CLEAR_COLLAPSE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-mode-history-overflow-clear-probe-check.ps1' `
    -FailureLabel 'Mode-history overflow/clear' `
    -EchoOnSuccess:$false `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true `
    -TrimEchoText:$true `
    -EmitSkippedSourceReceipt:$true `
    -InvokeArgs $invoke
$outputText = $probeState.Text

$clearLen = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_MODE_HISTORY_OVERFLOW_CLEAR_PROBE_CLEAR_LEN'
$clearHead = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_MODE_HISTORY_OVERFLOW_CLEAR_PROBE_CLEAR_HEAD'
$clearOverflow = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_MODE_HISTORY_OVERFLOW_CLEAR_PROBE_CLEAR_OVERFLOW'
$clearSeq = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_MODE_HISTORY_OVERFLOW_CLEAR_PROBE_CLEAR_SEQ'
$bootPreserveLen = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_MODE_HISTORY_OVERFLOW_CLEAR_PROBE_BOOT_PRESERVE_LEN'
if ($clearLen -ne 0 -or $clearHead -ne 0 -or $clearOverflow -ne 0 -or $clearSeq -ne 0 -or $bootPreserveLen -ne 3) {
    throw "Unexpected clear collapse. clearLen=$clearLen clearHead=$clearHead clearOverflow=$clearOverflow clearSeq=$clearSeq bootPreserveLen=$bootPreserveLen"
}

Write-Output 'BAREMETAL_QEMU_MODE_HISTORY_OVERFLOW_CLEAR_CLEAR_COLLAPSE_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_MODE_HISTORY_OVERFLOW_CLEAR_CLEAR_COLLAPSE_PROBE_SOURCE=baremetal-qemu-mode-history-overflow-clear-probe-check.ps1'
Write-Output "CLEAR_LEN=$clearLen"
Write-Output "CLEAR_HEAD=$clearHead"
Write-Output "CLEAR_OVERFLOW=$clearOverflow"
Write-Output "CLEAR_SEQ=$clearSeq"
Write-Output "BOOT_PRESERVE_LEN=$bootPreserveLen"
