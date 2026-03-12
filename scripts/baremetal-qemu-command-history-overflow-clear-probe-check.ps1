param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 90
)

$ErrorActionPreference = 'Stop'
function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $match = [regex]::Match($Text, '(?m)^' + [regex]::Escape($Name) + '=(-?\d+)\r?$')
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

function Invoke-Probe {
    param(
        [string] $Path,
        [hashtable] $Arguments,
        [string] $SuccessToken,
        [string] $SkipToken,
        [string] $Label
    )

    if (-not (Test-Path $Path)) { throw "$Label script not found: $Path" }

    $output = & $Path @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $text = ($output | Out-String)

    if ($text -match ('(?m)^' + [regex]::Escape($SkipToken) + '=skipped\r?$')) {
        return @{ Status = 'skipped'; Text = $text }
    }

    if ($exitCode -ne 0) {
        if ($text) { Write-Output $text.TrimEnd() }
        throw "$Label failed with exit code $exitCode"
    }

    if ($text -notmatch ('(?m)^' + [regex]::Escape($SuccessToken) + '=pass\r?$')) {
        if ($text) { Write-Output $text.TrimEnd() }
        throw "$Label did not report a pass token"
    }

    return @{ Status = 'pass'; Text = $text }
}
$args = @{ TimeoutSeconds = $TimeoutSeconds }
if ($SkipBuild) { $args.SkipBuild = $true }

$overflow = Invoke-Probe -Path (Join-Path $PSScriptRoot 'baremetal-qemu-command-health-history-probe-check.ps1') -Arguments $args -SuccessToken 'BAREMETAL_QEMU_COMMAND_HEALTH_HISTORY_PROBE' -SkipToken 'BAREMETAL_QEMU_COMMAND_HEALTH_HISTORY_PROBE' -Label 'command-health history probe'
if ($overflow.Status -eq 'skipped') {
    Write-Output 'BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_PROBE=skipped'
    Write-Output 'BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_PROBE_SOURCE=baremetal-qemu-command-health-history-probe-check.ps1,baremetal-qemu-bootdiag-history-clear-probe-check.ps1'
    exit 0
}

$clear = Invoke-Probe -Path (Join-Path $PSScriptRoot 'baremetal-qemu-bootdiag-history-clear-probe-check.ps1') -Arguments $args -SuccessToken 'BAREMETAL_QEMU_BOOTDIAG_HISTORY_CLEAR_PROBE' -SkipToken 'BAREMETAL_QEMU_BOOTDIAG_HISTORY_CLEAR_PROBE' -Label 'bootdiag/history clear probe'
if ($clear.Status -eq 'skipped') {
    Write-Output 'BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_PROBE=skipped'
    Write-Output 'BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_PROBE_SOURCE=baremetal-qemu-command-health-history-probe-check.ps1,baremetal-qemu-bootdiag-history-clear-probe-check.ps1'
    exit 0
}

$overflowCount = Extract-IntValue -Text $overflow.Text -Name 'COMMAND_HISTORY_OVERFLOW'
$firstSeq = Extract-IntValue -Text $overflow.Text -Name 'COMMAND_HISTORY_FIRST_SEQ'
$firstArg0 = Extract-IntValue -Text $overflow.Text -Name 'COMMAND_HISTORY_FIRST_ARG0'
$lastSeq = Extract-IntValue -Text $overflow.Text -Name 'COMMAND_HISTORY_LAST_SEQ'
$lastArg0 = Extract-IntValue -Text $overflow.Text -Name 'COMMAND_HISTORY_LAST_ARG0'
$clearLen = Extract-IntValue -Text $clear.Text -Name 'CMD_HISTORY_LEN2'
$clearFirstSeq = Extract-IntValue -Text $clear.Text -Name 'CMD_HISTORY_FIRST_SEQ'
$clearFirstOpcode = Extract-IntValue -Text $clear.Text -Name 'CMD_HISTORY_FIRST_OPCODE'
$clearFirstResult = Extract-IntValue -Text $clear.Text -Name 'CMD_HISTORY_FIRST_RESULT'
$healthPreserveLen = Extract-IntValue -Text $clear.Text -Name 'HEALTH_HISTORY_LEN2'
$restartLen = Extract-IntValue -Text $clear.Text -Name 'CMD_HISTORY_LEN3'
$restartSeq = Extract-IntValue -Text $clear.Text -Name 'CMD_HISTORY_SECOND_SEQ'
$restartOpcode = Extract-IntValue -Text $clear.Text -Name 'CMD_HISTORY_SECOND_OPCODE'
$restartResult = Extract-IntValue -Text $clear.Text -Name 'CMD_HISTORY_SECOND_RESULT'
$restartArg0 = Extract-IntValue -Text $clear.Text -Name 'CMD_HISTORY_SECOND_ARG0'

if (
    $overflowCount -ne 3 -or
    $firstSeq -ne 4 -or
    $firstArg0 -ne 103 -or
    $lastSeq -ne 35 -or
    $lastArg0 -ne 134 -or
    $clearLen -ne 1 -or
    $clearFirstSeq -ne 5 -or
    $clearFirstOpcode -ne 19 -or
    $clearFirstResult -ne 0 -or
    $healthPreserveLen -ne 6 -or
    $restartLen -ne 2 -or
    $restartSeq -ne 6 -or
    $restartOpcode -ne 20 -or
    $restartResult -ne 0 -or
    $restartArg0 -ne 0
) {
    throw "Unexpected command-history overflow/clear values: overflow=$overflowCount first=$firstSeq firstArg0=$firstArg0 last=$lastSeq lastArg0=$lastArg0 clearLen=$clearLen clearFirst=$clearFirstSeq clearOpcode=$clearFirstOpcode clearResult=$clearFirstResult healthPreserve=$healthPreserveLen restartLen=$restartLen restartSeq=$restartSeq restartOpcode=$restartOpcode restartResult=$restartResult restartArg0=$restartArg0"
}

Write-Output 'BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_PROBE_SOURCE=baremetal-qemu-command-health-history-probe-check.ps1,baremetal-qemu-bootdiag-history-clear-probe-check.ps1'
Write-Output "BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_PROBE_OVERFLOW_COUNT=$overflowCount"
Write-Output "BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_PROBE_FIRST_SEQ=$firstSeq"
Write-Output "BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_PROBE_FIRST_ARG0=$firstArg0"
Write-Output "BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_PROBE_LAST_SEQ=$lastSeq"
Write-Output "BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_PROBE_LAST_ARG0=$lastArg0"
Write-Output "BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_PROBE_CLEAR_LEN=$clearLen"
Write-Output "BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_PROBE_CLEAR_FIRST_SEQ=$clearFirstSeq"
Write-Output "BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_PROBE_CLEAR_FIRST_OPCODE=$clearFirstOpcode"
Write-Output "BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_PROBE_CLEAR_FIRST_RESULT=$clearFirstResult"
Write-Output "BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_PROBE_HEALTH_PRESERVE_LEN=$healthPreserveLen"
Write-Output "BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_PROBE_RESTART_LEN=$restartLen"
Write-Output "BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_PROBE_RESTART_SEQ=$restartSeq"
Write-Output "BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_PROBE_RESTART_OPCODE=$restartOpcode"
Write-Output "BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_PROBE_RESTART_RESULT=$restartResult"
Write-Output "BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_PROBE_RESTART_ARG0=$restartArg0"
