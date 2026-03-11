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
    Write-Output 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_SET_INIT_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying descriptor-bootdiag probe failed with exit code $probeExitCode"
}

$phaseAfterSetInit = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE_PHASE_AFTER_SET_INIT'
$lastCommandSeqAfterSetInit = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE_LAST_COMMAND_SEQ_AFTER_SET_INIT'
$phaseChangesAfterSetInit = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE_PHASE_CHANGES_AFTER_SET_INIT'

if ($null -in @($phaseAfterSetInit, $lastCommandSeqAfterSetInit, $phaseChangesAfterSetInit)) {
    throw 'Missing expected set-init fields in descriptor-bootdiag probe output.'
}
if ($phaseAfterSetInit -ne 1) { throw "Expected PHASE_AFTER_SET_INIT=1. got $phaseAfterSetInit" }
if ($lastCommandSeqAfterSetInit -ne 3) { throw "Expected LAST_COMMAND_SEQ_AFTER_SET_INIT=3. got $lastCommandSeqAfterSetInit" }
if ($phaseChangesAfterSetInit -ne 1) { throw "Expected PHASE_CHANGES_AFTER_SET_INIT=1. got $phaseChangesAfterSetInit" }

Write-Output 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_SET_INIT_PROBE=pass'
Write-Output "PHASE_AFTER_SET_INIT=$phaseAfterSetInit"
Write-Output "LAST_COMMAND_SEQ_AFTER_SET_INIT=$lastCommandSeqAfterSetInit"
Write-Output "PHASE_CHANGES_AFTER_SET_INIT=$phaseChangesAfterSetInit"
