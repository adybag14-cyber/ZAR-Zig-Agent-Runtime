# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-descriptor-bootdiag-probe-check.ps1"

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $pattern = '(?m)^' + [regex]::Escape($Name) + '=(-?\d+)\r?$'
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$probeOutput = if ($SkipBuild) { & $probe -SkipBuild 2>&1 } else { & $probe 2>&1 }
$probeExitCode = $LASTEXITCODE
$probeText = ($probeOutput | Out-String)
$probeOutput | Write-Output
if ($probeText -match 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE=skipped') {
    Write-Output 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_FINAL_STATE_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying descriptor-bootdiag probe failed with exit code $probeExitCode"
}

$mailboxOpcode = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE_MAILBOX_OPCODE'
$mailboxSeq = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE_MAILBOX_SEQ'
$descriptorInitBefore = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE_DESCRIPTOR_INIT_BEFORE'
$descriptorReadyAfterReinit = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE_DESCRIPTOR_READY_AFTER_REINIT'
$descriptorLoadedAfterReinit = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE_DESCRIPTOR_LOADED_AFTER_REINIT'
$descriptorInitAfterReinit = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE_DESCRIPTOR_INIT_AFTER_REINIT'
$bootSeqAfterReset = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE_BOOT_SEQ_AFTER_RESET'
$stackSnapshotAfterCapture = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE_STACK_SNAPSHOT_AFTER_CAPTURE'
$bootPhaseFinal = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE_BOOT_PHASE_FINAL'
$bootSeqFinal = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE_BOOT_SEQ_FINAL'
$lastCommandSeqFinal = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE_LAST_COMMAND_SEQ_FINAL'
$stackSnapshotFinal = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE_STACK_SNAPSHOT_FINAL'
$phaseChangesFinal = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE_PHASE_CHANGES_FINAL'
$descriptorReadyFinal = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE_DESCRIPTOR_READY_FINAL'
$descriptorLoadedFinal = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE_DESCRIPTOR_LOADED_FINAL'
$loadAttemptsBefore = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE_LOAD_ATTEMPTS_BEFORE'
$loadSuccessesBefore = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE_LOAD_SUCCESSES_BEFORE'
$loadAttemptsFinal = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE_LOAD_ATTEMPTS_FINAL'
$loadSuccessesFinal = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE_LOAD_SUCCESSES_FINAL'
$descriptorInitFinal = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE_DESCRIPTOR_INIT_FINAL'

if ($null -in @($mailboxOpcode, $mailboxSeq, $descriptorInitBefore, $descriptorReadyAfterReinit, $descriptorLoadedAfterReinit, $descriptorInitAfterReinit, $bootSeqAfterReset, $stackSnapshotAfterCapture, $bootPhaseFinal, $bootSeqFinal, $lastCommandSeqFinal, $stackSnapshotFinal, $phaseChangesFinal, $descriptorReadyFinal, $descriptorLoadedFinal, $loadAttemptsBefore, $loadSuccessesBefore, $loadAttemptsFinal, $loadSuccessesFinal, $descriptorInitFinal)) {
    throw 'Missing expected final-state fields in descriptor-bootdiag probe output.'
}
if ($mailboxOpcode -ne 10) { throw "Expected MAILBOX_OPCODE=10. got $mailboxOpcode" }
if ($mailboxSeq -ne 6) { throw "Expected MAILBOX_SEQ=6. got $mailboxSeq" }
if ($descriptorReadyAfterReinit -ne 1) { throw "Expected DESCRIPTOR_READY_AFTER_REINIT=1. got $descriptorReadyAfterReinit" }
if ($descriptorLoadedAfterReinit -ne 1) { throw "Expected DESCRIPTOR_LOADED_AFTER_REINIT=1. got $descriptorLoadedAfterReinit" }
if ($descriptorInitAfterReinit -ne ($descriptorInitBefore + 1)) { throw "Expected DESCRIPTOR_INIT_AFTER_REINIT=DESCRIPTOR_INIT_BEFORE+1. got $descriptorInitAfterReinit vs $descriptorInitBefore" }
if ($bootPhaseFinal -ne 1) { throw "Expected BOOT_PHASE_FINAL=1. got $bootPhaseFinal" }
if ($bootSeqFinal -ne $bootSeqAfterReset) { throw "Expected BOOT_SEQ_FINAL=BOOT_SEQ_AFTER_RESET. got $bootSeqFinal vs $bootSeqAfterReset" }
if ($lastCommandSeqFinal -ne 6) { throw "Expected LAST_COMMAND_SEQ_FINAL=6. got $lastCommandSeqFinal" }
if ($stackSnapshotFinal -ne $stackSnapshotAfterCapture) { throw "Expected STACK_SNAPSHOT_FINAL to equal captured snapshot. got $stackSnapshotFinal vs $stackSnapshotAfterCapture" }
if ($phaseChangesFinal -ne 1) { throw "Expected PHASE_CHANGES_FINAL=1. got $phaseChangesFinal" }
if ($descriptorReadyFinal -ne 1) { throw "Expected DESCRIPTOR_READY_FINAL=1. got $descriptorReadyFinal" }
if ($descriptorLoadedFinal -ne 1) { throw "Expected DESCRIPTOR_LOADED_FINAL=1. got $descriptorLoadedFinal" }
if ($loadAttemptsFinal -ne ($loadAttemptsBefore + 1)) { throw "Expected LOAD_ATTEMPTS_FINAL=LOAD_ATTEMPTS_BEFORE+1. got $loadAttemptsFinal vs $loadAttemptsBefore" }
if ($loadSuccessesFinal -ne ($loadSuccessesBefore + 1)) { throw "Expected LOAD_SUCCESSES_FINAL=LOAD_SUCCESSES_BEFORE+1. got $loadSuccessesFinal vs $loadSuccessesBefore" }
if ($descriptorInitFinal -ne $descriptorInitAfterReinit) { throw "Expected DESCRIPTOR_INIT_FINAL to equal DESCRIPTOR_INIT_AFTER_REINIT. got $descriptorInitFinal vs $descriptorInitAfterReinit" }

Write-Output 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_FINAL_STATE_PROBE=pass'
Write-Output "MAILBOX_OPCODE=$mailboxOpcode"
Write-Output "MAILBOX_SEQ=$mailboxSeq"
Write-Output "DESCRIPTOR_INIT_BEFORE=$descriptorInitBefore"
Write-Output "DESCRIPTOR_READY_AFTER_REINIT=$descriptorReadyAfterReinit"
Write-Output "DESCRIPTOR_LOADED_AFTER_REINIT=$descriptorLoadedAfterReinit"
Write-Output "DESCRIPTOR_INIT_AFTER_REINIT=$descriptorInitAfterReinit"
Write-Output "BOOT_PHASE_FINAL=$bootPhaseFinal"
Write-Output "BOOT_SEQ_FINAL=$bootSeqFinal"
Write-Output "LAST_COMMAND_SEQ_FINAL=$lastCommandSeqFinal"
Write-Output "STACK_SNAPSHOT_FINAL=$stackSnapshotFinal"
Write-Output "PHASE_CHANGES_FINAL=$phaseChangesFinal"
Write-Output "DESCRIPTOR_READY_FINAL=$descriptorReadyFinal"
Write-Output "DESCRIPTOR_LOADED_FINAL=$descriptorLoadedFinal"
Write-Output "LOAD_ATTEMPTS_FINAL=$loadAttemptsFinal"
Write-Output "LOAD_SUCCESSES_FINAL=$loadSuccessesFinal"
Write-Output "DESCRIPTOR_INIT_FINAL=$descriptorInitFinal"
