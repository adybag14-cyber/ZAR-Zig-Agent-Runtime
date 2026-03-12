param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 30,
    [int] $GdbPort = 0
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-mode-boot-phase-history-probe-check.ps1"

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $pattern = '(?m)^' + [regex]::Escape($Name) + '=(-?\d+)\r?$'
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$invoke = @{ TimeoutSeconds = $TimeoutSeconds }
if ($GdbPort -gt 0) { $invoke.GdbPort = $GdbPort }
if ($SkipBuild) { $invoke.SkipBuild = $true }

$probeOutput = & $probe @invoke 2>&1
$probeExitCode = $LASTEXITCODE
$probeText = ($probeOutput | Out-String)
$probeOutput | Write-Output
if ($probeText -match '(?m)^BAREMETAL_QEMU_MODE_BOOT_PHASE_HISTORY_PROBE=skipped\r?$') {
    Write-Output 'BAREMETAL_QEMU_MODE_BOOT_PHASE_HISTORY_BOOT_SEMANTICS_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying mode/boot-phase history probe failed with exit code $probeExitCode"
}

$expected = [ordered]@{
    'BOOT_SEMANTIC_LEN' = 3
    'BOOT_SEM0_PREV' = 2
    'BOOT_SEM0_NEW' = 1
    'BOOT_SEM0_REASON' = 1
    'BOOT_SEM1_PREV' = 1
    'BOOT_SEM1_NEW' = 2
    'BOOT_SEM1_REASON' = 2
    'BOOT_SEM2_PREV' = 2
    'BOOT_SEM2_NEW' = 255
    'BOOT_SEM2_REASON' = 3
}

foreach ($entry in $expected.GetEnumerator()) {
    $actual = Extract-IntValue -Text $probeText -Name $entry.Key
    if ($null -eq $actual) { throw "Missing output value for $($entry.Key)" }
    if ($actual -ne $entry.Value) { throw "Unexpected $($entry.Key): got $actual expected $($entry.Value)" }
}

Write-Output 'BAREMETAL_QEMU_MODE_BOOT_PHASE_HISTORY_BOOT_SEMANTICS_PROBE=pass'
Write-Output 'BOOT_SEMANTIC_LEN=3'
Write-Output 'BOOT_SEM0_PREV=2'
Write-Output 'BOOT_SEM0_NEW=1'
Write-Output 'BOOT_SEM0_REASON=1'
Write-Output 'BOOT_SEM1_PREV=1'
Write-Output 'BOOT_SEM1_NEW=2'
Write-Output 'BOOT_SEM1_REASON=2'
Write-Output 'BOOT_SEM2_PREV=2'
Write-Output 'BOOT_SEM2_NEW=255'
Write-Output 'BOOT_SEM2_REASON=3'
