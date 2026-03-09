param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-interrupt-timeout-disable-enable-probe-check.ps1"
$waitConditionInterruptAny = 3
$taskStateWaiting = 6

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
if ($probeText -match 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_ENABLE_PROBE=skipped') {
    Write-Output 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_ENABLE_DEADLINE_HOLD_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying interrupt-timeout disable-enable probe failed with exit code $probeExitCode"
}

$armedWaitTimeout = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_ENABLE_PROBE_ARMED_WAIT_TIMEOUT'
$pausedTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_ENABLE_PROBE_PAUSED_TICK'
$pausedWaitKind0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_ENABLE_PROBE_PAUSED_WAIT_KIND0'
$pausedWaitTimeout0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_ENABLE_PROBE_PAUSED_WAIT_TIMEOUT0'
$pausedTask0State = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_ENABLE_PROBE_PAUSED_TASK0_STATE'

if ($null -in @($armedWaitTimeout, $pausedTick, $pausedWaitKind0, $pausedWaitTimeout0, $pausedTask0State)) {
    throw 'Missing expected paused-window deadline fields in probe output.'
}
if ($pausedTick -le $armedWaitTimeout) {
    throw "Expected paused disabled window to survive past the original timeout deadline. pausedTick=$pausedTick armedWaitTimeout=$armedWaitTimeout"
}
if ($pausedWaitKind0 -ne $waitConditionInterruptAny) {
    throw "Expected wait kind to remain interrupt_any past the original deadline while timers are disabled. got $pausedWaitKind0"
}
if ($pausedWaitTimeout0 -ne $armedWaitTimeout) {
    throw "Expected original timeout deadline to stay preserved through the paused window. armed=$armedWaitTimeout paused=$pausedWaitTimeout0"
}
if ($pausedTask0State -ne $taskStateWaiting) {
    throw "Expected task to remain waiting past the original deadline while timers are disabled. got state=$pausedTask0State"
}

Write-Output 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_ENABLE_DEADLINE_HOLD_PROBE=pass'
Write-Output "ARMED_WAIT_TIMEOUT=$armedWaitTimeout"
Write-Output "PAUSED_TICK=$pausedTick"
Write-Output "PAUSED_WAIT_KIND0=$pausedWaitKind0"
Write-Output "PAUSED_WAIT_TIMEOUT0=$pausedWaitTimeout0"
Write-Output "PAUSED_TASK0_STATE=$pausedTask0State"
