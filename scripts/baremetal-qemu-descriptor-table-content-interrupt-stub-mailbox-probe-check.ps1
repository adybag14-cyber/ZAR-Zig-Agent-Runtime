param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-descriptor-table-content-probe-check.ps1"

function Extract-Value {
    param([string] $Text, [string] $Name)
    $pattern = '(?m)^' + [regex]::Escape($Name) + '=(.+?)\r?$'
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { return $null }
    return $match.Groups[1].Value.Trim()
}

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $pattern = '(?m)^' + [regex]::Escape($Name) + '=(-?\d+)\r?$'
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

function Extract-Field {
    param([string] $BroadText, [string] $RawText, [string] $Name)
    $value = Extract-IntValue -Text $BroadText -Name $Name
    if ($null -ne $value) { return $value }
    return Extract-IntValue -Text $RawText -Name $Name
}

$probeOutput = if ($SkipBuild) { & $probe -SkipBuild 2>&1 } else { & $probe 2>&1 }
$probeExitCode = $LASTEXITCODE
$probeText = ($probeOutput | Out-String)
$probeOutput | Write-Output
if ($probeText -match 'BAREMETAL_QEMU_DESCRIPTOR_TABLE_CONTENT_PROBE=skipped') {
    Write-Output 'BAREMETAL_QEMU_DESCRIPTOR_TABLE_CONTENT_INTERRUPT_STUB_MAILBOX_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying descriptor-table-content probe failed with exit code $probeExitCode"
}

$gdbStdout = Extract-Value -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_TABLE_CONTENT_PROBE_GDB_STDOUT'
if ([string]::IsNullOrWhiteSpace($gdbStdout) -or -not (Test-Path $gdbStdout)) {
    throw 'Missing descriptor-table-content GDB stdout log path.'
}
$rawText = Get-Content -Raw $gdbStdout

$stubSymbol = Extract-Field -BroadText $probeText -RawText $rawText -Name 'INTERRUPT_STUB_SYMBOL'
$idt0Handler = Extract-Field -BroadText $probeText -RawText $rawText -Name 'IDT0_HANDLER_ADDR'
$idt255Handler = Extract-Field -BroadText $probeText -RawText $rawText -Name 'IDT255_HANDLER_ADDR'
$mailboxOpcode = Extract-Field -BroadText $probeText -RawText $rawText -Name 'MAILBOX_OPCODE'
$mailboxSeq = Extract-Field -BroadText $probeText -RawText $rawText -Name 'MAILBOX_SEQ'
$attemptsBefore = Extract-Field -BroadText $probeText -RawText $rawText -Name 'LOAD_ATTEMPTS_BEFORE'
$attemptsFinal = Extract-Field -BroadText $probeText -RawText $rawText -Name 'LOAD_ATTEMPTS_FINAL'
$successBefore = Extract-Field -BroadText $probeText -RawText $rawText -Name 'LOAD_SUCCESSES_BEFORE'
$successFinal = Extract-Field -BroadText $probeText -RawText $rawText -Name 'LOAD_SUCCESSES_FINAL'
$initAfter = Extract-Field -BroadText $probeText -RawText $rawText -Name 'DESCRIPTOR_INIT_AFTER_REINIT'
$initFinal = Extract-Field -BroadText $probeText -RawText $rawText -Name 'DESCRIPTOR_INIT_FINAL'

if ($null -in @($stubSymbol, $idt0Handler, $idt255Handler, $mailboxOpcode, $mailboxSeq, $attemptsBefore, $attemptsFinal, $successBefore, $successFinal, $initAfter, $initFinal)) {
    throw 'Missing interrupt-stub/mailbox fields.'
}
if ($idt0Handler -ne $stubSymbol -or $idt255Handler -ne $stubSymbol) {
    throw 'Unexpected interrupt stub wiring in IDT handlers.'
}
if ($mailboxOpcode -ne 10 -or $mailboxSeq -ne 2) {
    throw "Unexpected final mailbox state: opcode=$mailboxOpcode seq=$mailboxSeq"
}
if ($attemptsFinal -ne ($attemptsBefore + 1)) {
    throw "Expected final load attempts to increase by one. got $attemptsBefore -> $attemptsFinal"
}
if ($successFinal -ne ($successBefore + 1)) {
    throw "Expected final load successes to increase by one. got $successBefore -> $successFinal"
}
if ($initFinal -ne $initAfter) {
    throw "Expected descriptor init count to stabilize after load. got $initAfter -> $initFinal"
}

Write-Output 'BAREMETAL_QEMU_DESCRIPTOR_TABLE_CONTENT_INTERRUPT_STUB_MAILBOX_PROBE=pass'
Write-Output "MAILBOX_OPCODE=$mailboxOpcode"
Write-Output "MAILBOX_SEQ=$mailboxSeq"
Write-Output "INTERRUPT_STUB_SYMBOL=$stubSymbol"
