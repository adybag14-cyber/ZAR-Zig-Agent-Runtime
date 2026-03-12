param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 45,
    [int] $GdbPort = 0
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot 'baremetal-qemu-syscall-saturation-reset-probe-check.ps1'
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
$text = ($output | Out-String)
if ($text -match '(?m)^BAREMETAL_QEMU_SYSCALL_SATURATION_RESET_PROBE=skipped\r?$') {
    if ($text) { Write-Output $text.TrimEnd() }
    Write-Output 'BAREMETAL_QEMU_SYSCALL_SATURATION_RESET_FRESH_INVOKE_PROBE=skipped'
    Write-Output 'BAREMETAL_QEMU_SYSCALL_SATURATION_RESET_FRESH_INVOKE_PROBE_SOURCE=baremetal-qemu-syscall-saturation-reset-probe-check.ps1'
    exit 0
}
if ($exitCode -ne 0) {
    if ($text) { Write-Output $text.TrimEnd() }
    throw "Syscall saturation-reset prerequisite probe failed with exit code $exitCode"
}

$expected = @{
    'FRESH_ID' = 777
    'FRESH_TOKEN' = 53261
    'FRESH_INVOKE_COUNT' = 1
    'FRESH_LAST_ARG' = 153
    'FRESH_LAST_RESULT' = 54173
    'SECOND_SLOT_STATE' = 0
    'DISPATCH_COUNT' = 1
    'LAST_ID' = 777
    'STATE_LAST_RESULT' = 54173
}
foreach ($entry in $expected.GetEnumerator()) {
    $actual = Extract-IntValue -Text $text -Name $entry.Key
    if ($null -eq $actual) { throw "Missing output value for $($entry.Key)" }
    if ($actual -ne $entry.Value) { throw "Unexpected $($entry.Key): got $actual expected $($entry.Value)" }
}
$invokeTick = Extract-IntValue -Text $text -Name 'INVOKE_TICK'
if ($null -eq $invokeTick -or $invokeTick -le 0) { throw "Expected INVOKE_TICK > 0. got $invokeTick" }

Write-Output 'BAREMETAL_QEMU_SYSCALL_SATURATION_RESET_FRESH_INVOKE_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_SYSCALL_SATURATION_RESET_FRESH_INVOKE_PROBE_SOURCE=baremetal-qemu-syscall-saturation-reset-probe-check.ps1'
Write-Output 'FRESH_ID=777'
Write-Output 'FRESH_TOKEN=53261'
Write-Output 'FRESH_INVOKE_COUNT=1'
Write-Output 'FRESH_LAST_ARG=153'
Write-Output 'FRESH_LAST_RESULT=54173'
Write-Output 'SECOND_SLOT_STATE=0'
Write-Output 'DISPATCH_COUNT=1'
Write-Output 'LAST_ID=777'
Write-Output 'STATE_LAST_RESULT=54173'
Write-Output "INVOKE_TICK=$invokeTick"
