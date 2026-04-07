# SPDX-License-Identifier: GPL-2.0-only
function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $match = [regex]::Match($Text, '(?m)^' + [regex]::Escape($Name) + '=(-?\d+)\r?$')
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

function Extract-BoolValue {
    param([string] $Text, [string] $Name)
    $match = [regex]::Match($Text, '(?m)^' + [regex]::Escape($Name) + '=(True|False)\r?$')
    if (-not $match.Success) { return $null }
    return [bool]::Parse($match.Groups[1].Value)
}

function Extract-Value {
    param([string] $Text, [string] $Name)
    $match = [regex]::Match($Text, '(?m)^' + [regex]::Escape($Name) + '=(.+?)\r?$')
    if (-not $match.Success) { return $null }
    return $match.Groups[1].Value.Trim()
}

function Extract-Field {
    param([string] $BroadText, [string] $RawText, [string] $Name)
    $value = Extract-IntValue -Text $BroadText -Name $Name
    if ($null -ne $value) { return $value }
    return Extract-IntValue -Text $RawText -Name $Name
}

function Get-RawProbeText {
    param(
        [string] $ProbeText,
        [string] $PathFieldName,
        [string] $MissingMessage
    )

    $rawPath = Extract-Value -Text $ProbeText -Name $PathFieldName
    if ([string]::IsNullOrWhiteSpace($rawPath) -or -not (Test-Path $rawPath)) {
        throw $MissingMessage
    }

    return Get-Content -Raw $rawPath
}

function Invoke-WrapperProbe {
    param(
        [Parameter(Mandatory = $true)][string] $ProbePath,
        [switch] $SkipBuild,
        [Parameter(Mandatory = $true)][string] $SkippedPattern,
        [Parameter(Mandatory = $true)][string] $SkippedReceipt,
        [Parameter(Mandatory = $true)][string] $SkippedSourceReceipt,
        [Parameter(Mandatory = $true)][string] $SkippedSourceValue,
        [Parameter(Mandatory = $true)][string] $FailureLabel,
        [hashtable] $InvokeArgs = @{},
        [bool] $EchoOnSuccess = $true,
        [bool] $EchoOnSkip = $true,
        [bool] $EchoOnFailure = $true,
        [bool] $TrimEchoText = $false,
        [bool] $EmitSkippedSourceReceipt = $true
    )

    $callArgs = @{}
    foreach ($key in $InvokeArgs.Keys) { $callArgs[$key] = $InvokeArgs[$key] }
    if ($SkipBuild) { $callArgs.SkipBuild = $true }
    $probeOutput = & $ProbePath @callArgs 2>&1
    $probeExitCode = $LASTEXITCODE
    $probeText = ($probeOutput | Out-String)
    $echoText = if ($TrimEchoText) { $probeText.TrimEnd() } else { $probeText }
    $hasEchoText = -not [string]::IsNullOrWhiteSpace($echoText)
    if ($probeText -match $SkippedPattern) {
        if ($EchoOnSkip -and $hasEchoText) { Write-Output $echoText }
        Write-Output ("{0}=skipped" -f $SkippedReceipt)
        if ($EmitSkippedSourceReceipt) { Write-Output ("{0}={1}" -f $SkippedSourceReceipt, $SkippedSourceValue) }
        exit 0
    }
    if ($probeExitCode -ne 0) {
        if ($EchoOnFailure -and $hasEchoText) { Write-Output $echoText }
        throw ("Underlying {0} probe failed with exit code {1}" -f $FailureLabel, $probeExitCode)
    }
    if ($EchoOnSuccess -and $hasEchoText) { Write-Output $echoText }

    return @{ Text = $probeText; ExitCode = $probeExitCode }
}
