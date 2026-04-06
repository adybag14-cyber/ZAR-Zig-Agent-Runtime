# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-interrupt-mask-clear-all-recovery-probe-check.ps1"

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_INTERRUPT_MASK_CLEAR_ALL_RECOVERY_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_INTERRUPT_MASK_CLEAR_ALL_RECOVERY_HISTORY_PAYLOAD_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_INTERRUPT_MASK_CLEAR_ALL_RECOVERY_HISTORY_PAYLOAD_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-interrupt-mask-clear-all-recovery-probe-check.ps1' `
    -FailureLabel 'interrupt-mask-clear-all-recovery'
$probeText = $probeState.Text

$interruptCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_INTERRUPT_COUNT'
$lastInterruptVector = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_LAST_INTERRUPT_VECTOR'
$historyLen = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_INTERRUPT_HISTORY_LEN'
$historySeq = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_INTERRUPT_HISTORY0_SEQ'
$historyVector = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_INTERRUPT_HISTORY0_VECTOR'
$historyIsException = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_INTERRUPT_HISTORY0_IS_EXCEPTION'
$historyCode = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_INTERRUPT_HISTORY0_CODE'
$historyInterruptCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_INTERRUPT_HISTORY0_INTERRUPT_COUNT'
$historyExceptionCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_INTERRUPT_HISTORY0_EXCEPTION_COUNT'
if ($null -in @($interruptCount, $lastInterruptVector, $historyLen, $historySeq, $historyVector, $historyIsException, $historyCode, $historyInterruptCount, $historyExceptionCount)) {
    throw 'Missing history-payload fields in interrupt-mask-clear-all-recovery probe output.'
}
if ($interruptCount -ne 1) { throw "Expected INTERRUPT_COUNT=1, got $interruptCount" }
if ($lastInterruptVector -ne 200) { throw "Expected LAST_INTERRUPT_VECTOR=200, got $lastInterruptVector" }
if ($historyLen -ne 1) { throw "Expected INTERRUPT_HISTORY_LEN=1, got $historyLen" }
if ($historySeq -ne 1) { throw "Expected INTERRUPT_HISTORY0_SEQ=1, got $historySeq" }
if ($historyVector -ne 200) { throw "Expected INTERRUPT_HISTORY0_VECTOR=200, got $historyVector" }
if ($historyIsException -ne 0) { throw "Expected INTERRUPT_HISTORY0_IS_EXCEPTION=0, got $historyIsException" }
if ($historyCode -ne 0) { throw "Expected INTERRUPT_HISTORY0_CODE=0, got $historyCode" }
if ($historyInterruptCount -ne 1) { throw "Expected INTERRUPT_HISTORY0_INTERRUPT_COUNT=1, got $historyInterruptCount" }
if ($historyExceptionCount -ne 0) { throw "Expected INTERRUPT_HISTORY0_EXCEPTION_COUNT=0, got $historyExceptionCount" }
Write-Output 'BAREMETAL_QEMU_INTERRUPT_MASK_CLEAR_ALL_RECOVERY_HISTORY_PAYLOAD_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_INTERRUPT_MASK_CLEAR_ALL_RECOVERY_HISTORY_PAYLOAD_PROBE_SOURCE=baremetal-qemu-interrupt-mask-clear-all-recovery-probe-check.ps1'
Write-Output "INTERRUPT_COUNT=$interruptCount"
Write-Output "LAST_INTERRUPT_VECTOR=$lastInterruptVector"
Write-Output "INTERRUPT_HISTORY_LEN=$historyLen"
Write-Output "INTERRUPT_HISTORY0_SEQ=$historySeq"
Write-Output "INTERRUPT_HISTORY0_VECTOR=$historyVector"
Write-Output "INTERRUPT_HISTORY0_IS_EXCEPTION=$historyIsException"
Write-Output "INTERRUPT_HISTORY0_CODE=$historyCode"
Write-Output "INTERRUPT_HISTORY0_INTERRUPT_COUNT=$historyInterruptCount"
Write-Output "INTERRUPT_HISTORY0_EXCEPTION_COUNT=$historyExceptionCount"
