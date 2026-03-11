param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-descriptor-dispatch-probe-check.ps1"

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
if ($probeText -match 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE=skipped') {
    Write-Output 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_TELEMETRY_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying descriptor-dispatch probe failed with exit code $probeExitCode"
}

$initBefore = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_DESCRIPTOR_INIT_BEFORE'
$attemptsBefore = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_LOAD_ATTEMPTS_BEFORE'
$successBefore = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_LOAD_SUCCESSES_BEFORE'
$initFinal = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_DESCRIPTOR_INIT_FINAL'
$attemptsFinal = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_LOAD_ATTEMPTS_FINAL'
$successFinal = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_LOAD_SUCCESSES_FINAL'
$ready = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_DESCRIPTOR_READY_FINAL'
$loaded = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_DESCRIPTOR_LOADED_FINAL'

if ($null -in @($initBefore, $attemptsBefore, $successBefore, $initFinal, $attemptsFinal, $successFinal, $ready, $loaded)) {
    throw 'Missing descriptor telemetry fields in descriptor-dispatch probe output.'
}
if ($initBefore -lt 1) { throw "Expected DESCRIPTOR_INIT_BEFORE>=1. got $initBefore" }
if ($initFinal -ne ($initBefore + 1)) { throw "Expected DESCRIPTOR_INIT_FINAL=DESCRIPTOR_INIT_BEFORE+1. got $initBefore -> $initFinal" }
if ($attemptsFinal -ne ($attemptsBefore + 1)) { throw "Expected LOAD_ATTEMPTS_FINAL=LOAD_ATTEMPTS_BEFORE+1. got $attemptsBefore -> $attemptsFinal" }
if ($successFinal -ne ($successBefore + 1)) { throw "Expected LOAD_SUCCESSES_FINAL=LOAD_SUCCESSES_BEFORE+1. got $successBefore -> $successFinal" }
if ($ready -ne 1) { throw "Expected DESCRIPTOR_READY_FINAL=1. got $ready" }
if ($loaded -ne 1) { throw "Expected DESCRIPTOR_LOADED_FINAL=1. got $loaded" }

Write-Output 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_TELEMETRY_PROBE=pass'
Write-Output "DESCRIPTOR_INIT_BEFORE=$initBefore"
Write-Output "DESCRIPTOR_INIT_FINAL=$initFinal"
Write-Output "LOAD_ATTEMPTS_BEFORE=$attemptsBefore"
Write-Output "LOAD_ATTEMPTS_FINAL=$attemptsFinal"
Write-Output "LOAD_SUCCESSES_BEFORE=$successBefore"
Write-Output "LOAD_SUCCESSES_FINAL=$successFinal"
Write-Output "DESCRIPTOR_READY_FINAL=$ready"
Write-Output "DESCRIPTOR_LOADED_FINAL=$loaded"
