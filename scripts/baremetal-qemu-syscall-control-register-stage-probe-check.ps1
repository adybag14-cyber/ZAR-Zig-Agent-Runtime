param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 45,
    [int] $GdbPort = 1287
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot 'baremetal-qemu-syscall-control-probe-check.ps1'
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $match = [regex]::Match($Text, '(?m)^' + [regex]::Escape($Name) + '=(-?\d+)\r?$')
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$invoke = @{ TimeoutSeconds = $TimeoutSeconds; GdbPort = $GdbPort }
if ($SkipBuild) { $invoke.SkipBuild = $true }

$output = & $probe @invoke 2>&1
$exitCode = $LASTEXITCODE
$outputText = ($output | Out-String)
if ($outputText -match '(?m)^BAREMETAL_QEMU_SYSCALL_CONTROL_PROBE=skipped\r?$') {
    if ($outputText) { Write-Output $outputText.TrimEnd() }
    Write-Output 'BAREMETAL_QEMU_SYSCALL_CONTROL_REGISTER_STAGE_PROBE=skipped'
    Write-Output 'BAREMETAL_QEMU_SYSCALL_CONTROL_REGISTER_STAGE_PROBE_SOURCE=baremetal-qemu-syscall-control-probe-check.ps1'
    exit 0
}
if ($exitCode -ne 0) {
    if ($outputText) { Write-Output $outputText.TrimEnd() }
    throw "Syscall control prerequisite probe failed with exit code $exitCode"
}

$registerEntryCount = Extract-IntValue -Text $outputText -Name 'REGISTER_ENTRY_COUNT'
$registerEntryState = Extract-IntValue -Text $outputText -Name 'REGISTER_ENTRY_STATE'
$registerEntryFlags = Extract-IntValue -Text $outputText -Name 'REGISTER_ENTRY_FLAGS'
$registerToken = Extract-IntValue -Text $outputText -Name 'REGISTER_TOKEN'

if ($registerEntryCount -ne 1) { throw "Expected REGISTER_ENTRY_COUNT=1. got $registerEntryCount" }
if ($registerEntryState -ne 1) { throw "Expected REGISTER_ENTRY_STATE=1. got $registerEntryState" }
if ($registerEntryFlags -ne 0) { throw "Expected REGISTER_ENTRY_FLAGS=0. got $registerEntryFlags" }
if ($registerToken -ne 48879) { throw "Expected REGISTER_TOKEN=48879. got $registerToken" }

Write-Output 'BAREMETAL_QEMU_SYSCALL_CONTROL_REGISTER_STAGE_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_SYSCALL_CONTROL_REGISTER_STAGE_PROBE_SOURCE=baremetal-qemu-syscall-control-probe-check.ps1'
Write-Output "REGISTER_ENTRY_COUNT=$registerEntryCount"
Write-Output "REGISTER_ENTRY_STATE=$registerEntryState"
Write-Output "REGISTER_ENTRY_FLAGS=$registerEntryFlags"
Write-Output "REGISTER_TOKEN=$registerToken"
