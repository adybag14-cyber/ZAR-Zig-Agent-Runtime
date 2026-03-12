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
    Write-Output 'BAREMETAL_QEMU_SYSCALL_CONTROL_REREGISTER_STAGE_PROBE=skipped'
    Write-Output 'BAREMETAL_QEMU_SYSCALL_CONTROL_REREGISTER_STAGE_PROBE_SOURCE=baremetal-qemu-syscall-control-probe-check.ps1'
    exit 0
}
if ($exitCode -ne 0) {
    if ($outputText) { Write-Output $outputText.TrimEnd() }
    throw "Syscall control prerequisite probe failed with exit code $exitCode"
}

$updatedToken = Extract-IntValue -Text $outputText -Name 'UPDATED_TOKEN'
$reregisterEntryCount = Extract-IntValue -Text $outputText -Name 'REREGISTER_ENTRY_COUNT'
$reregisterInvokeCount = Extract-IntValue -Text $outputText -Name 'REREGISTER_INVOKE_COUNT'

if ($updatedToken -ne 51966) { throw "Expected UPDATED_TOKEN=51966. got $updatedToken" }
if ($reregisterEntryCount -ne 1) { throw "Expected REREGISTER_ENTRY_COUNT=1. got $reregisterEntryCount" }
if ($reregisterInvokeCount -ne 0) { throw "Expected REREGISTER_INVOKE_COUNT=0. got $reregisterInvokeCount" }

Write-Output 'BAREMETAL_QEMU_SYSCALL_CONTROL_REREGISTER_STAGE_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_SYSCALL_CONTROL_REREGISTER_STAGE_PROBE_SOURCE=baremetal-qemu-syscall-control-probe-check.ps1'
Write-Output "UPDATED_TOKEN=$updatedToken"
Write-Output "REREGISTER_ENTRY_COUNT=$reregisterEntryCount"
Write-Output "REREGISTER_INVOKE_COUNT=$reregisterInvokeCount"
