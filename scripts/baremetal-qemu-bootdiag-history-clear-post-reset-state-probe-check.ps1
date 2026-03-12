param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 90
)

$ErrorActionPreference = 'Stop'
$probe = Join-Path $PSScriptRoot 'baremetal-qemu-bootdiag-history-clear-probe-check.ps1'
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $match = [regex]::Match($Text, '(?m)^' + [regex]::Escape($Name) + '=(-?\d+)\r?$')
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$invoke = @{ TimeoutSeconds = $TimeoutSeconds }
if ($SkipBuild) { $invoke.SkipBuild = $true }

$output = & $probe @invoke 2>&1
$exitCode = $LASTEXITCODE
$outputText = ($output | Out-String)
if ($outputText -match '(?m)^BAREMETAL_QEMU_BOOTDIAG_HISTORY_CLEAR_PROBE=skipped\r?$') {
    if ($outputText) { Write-Output $outputText.TrimEnd() }
    Write-Output 'BAREMETAL_QEMU_BOOTDIAG_HISTORY_CLEAR_POST_RESET_STATE_PROBE=skipped'
    Write-Output 'BAREMETAL_QEMU_BOOTDIAG_HISTORY_CLEAR_POST_RESET_STATE_PROBE_SOURCE=baremetal-qemu-bootdiag-history-clear-probe-check.ps1'
    exit 0
}
if ($exitCode -ne 0) {
    if ($outputText) { Write-Output $outputText.TrimEnd() }
    throw "Bootdiag/history-clear prerequisite probe failed with exit code $exitCode"
}

$phase = Extract-IntValue -Text $outputText -Name 'BOOTDIAG_PHASE'
$bootSeq = Extract-IntValue -Text $outputText -Name 'BOOTDIAG_BOOT_SEQ'
$lastSeq = Extract-IntValue -Text $outputText -Name 'BOOTDIAG_LAST_SEQ'
$lastTick = Extract-IntValue -Text $outputText -Name 'BOOTDIAG_LAST_TICK'
$observedTick = Extract-IntValue -Text $outputText -Name 'BOOTDIAG_OBSERVED_TICK'
$stack = Extract-IntValue -Text $outputText -Name 'BOOTDIAG_STACK'
$phaseChanges = Extract-IntValue -Text $outputText -Name 'BOOTDIAG_PHASE_CHANGES'
$statusMode = Extract-IntValue -Text $outputText -Name 'STATUS_MODE_RESET'
$bootHistoryLen = Extract-IntValue -Text $outputText -Name 'BOOT_HISTORY_LEN'

if ($phase -ne 2 -or $bootSeq -ne 1 -or $lastSeq -ne 4 -or $lastTick -ne 3 -or $observedTick -ne 4 -or $stack -ne 0 -or $phaseChanges -ne 0 -or $statusMode -ne 1 -or $bootHistoryLen -ne 3) {
    throw "Unexpected post-reset state. phase=$phase bootSeq=$bootSeq lastSeq=$lastSeq lastTick=$lastTick observedTick=$observedTick stack=$stack phaseChanges=$phaseChanges statusMode=$statusMode bootHistoryLen=$bootHistoryLen"
}

Write-Output 'BAREMETAL_QEMU_BOOTDIAG_HISTORY_CLEAR_POST_RESET_STATE_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_BOOTDIAG_HISTORY_CLEAR_POST_RESET_STATE_PROBE_SOURCE=baremetal-qemu-bootdiag-history-clear-probe-check.ps1'
Write-Output "BOOTDIAG_PHASE=$phase"
Write-Output "BOOTDIAG_BOOT_SEQ=$bootSeq"
Write-Output "BOOTDIAG_LAST_SEQ=$lastSeq"
Write-Output "BOOTDIAG_LAST_TICK=$lastTick"
Write-Output "BOOTDIAG_OBSERVED_TICK=$observedTick"
Write-Output "BOOTDIAG_STACK=$stack"
Write-Output "BOOTDIAG_PHASE_CHANGES=$phaseChanges"
Write-Output "STATUS_MODE_RESET=$statusMode"
Write-Output "BOOT_HISTORY_LEN=$bootHistoryLen"
