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

function Test-WrapperSkipped {
    param(
        [string] $ProbeText,
        [string] $SkippedPattern
    )

    if ($ProbeText -match $SkippedPattern) { return $true }

    $normalizedPattern = $SkippedPattern.Replace('\\r', '\r').Replace('\\n', '\n')
    if ($normalizedPattern -ne $SkippedPattern -and $ProbeText -match $normalizedPattern) { return $true }

    return $false
}

function Invoke-ProbeScriptProcess {
    param(
        [Parameter(Mandatory = $true)][string] $ProbePath,
        [switch] $SkipBuild,
        [hashtable] $InvokeArgs = @{}
    )

    $pwshPath = (Get-Command pwsh -ErrorAction Stop).Path
    $argList = @('-NoLogo', '-NoProfile', '-File', $ProbePath)

    foreach ($key in $InvokeArgs.Keys) {
        $value = $InvokeArgs[$key]
        if ($null -eq $value) { continue }
        if ($value -is [switch] -or $value -is [bool]) {
            if ([bool]$value) {
                $argList += "-$key"
            }
            continue
        }
        $argList += "-$key"
        $argList += [string]$value
    }

    if ($SkipBuild) {
        $argList += '-SkipBuild'
    }

    $probeOutput = & $pwshPath @argList 2>&1
    $probeExitCode = $LASTEXITCODE

    return @{
        Output = $probeOutput
        ExitCode = $probeExitCode
    }
}

function Invoke-WrapperProbe {
    param(
        [Parameter(Mandatory = $true)][string] $ProbePath,
        [switch] $SkipBuild,
        [Parameter(Mandatory = $true)][string] $SkippedPattern,
        [Parameter(Mandatory = $true)][string] $SkippedReceipt,
        [string] $SkippedSourceReceipt = '',
        [string] $SkippedSourceValue = '',
        [Parameter(Mandatory = $true)][string] $FailureLabel,
        [hashtable] $InvokeArgs = @{},
        [bool] $EchoOnSuccess = $true,
        [bool] $EchoOnSkip = $true,
        [bool] $EchoOnFailure = $true,
        [bool] $TrimEchoText = $false,
        [bool] $EmitSkippedSourceReceipt = $true
    )

    $probeState = Invoke-ProbeScriptProcess -ProbePath $ProbePath -SkipBuild:$SkipBuild -InvokeArgs $InvokeArgs
    $probeOutput = $probeState.Output
    $probeExitCode = $probeState.ExitCode
    $probeText = ($probeOutput | Out-String)
    $echoText = if ($TrimEchoText) { $probeText.TrimEnd() } else { $probeText }
    $hasEchoText = -not [string]::IsNullOrWhiteSpace($echoText)
    if (Test-WrapperSkipped -ProbeText $probeText -SkippedPattern $SkippedPattern) {
        if ($EchoOnSkip -and $hasEchoText) { Write-Output $echoText }
        Write-Output ("{0}=skipped" -f $SkippedReceipt)
        if ($EmitSkippedSourceReceipt -and -not [string]::IsNullOrWhiteSpace($SkippedSourceReceipt)) {
            Write-Output ("{0}={1}" -f $SkippedSourceReceipt, $SkippedSourceValue)
        }
        exit 0
    }
    if ($probeExitCode -ne 0) {
        if ($EchoOnFailure -and $hasEchoText) { Write-Output $echoText }
        throw ("Underlying {0} probe failed with exit code {1}" -f $FailureLabel, $probeExitCode)
    }
    if ($EchoOnSuccess -and $hasEchoText) { Write-Output $echoText }

    return @{ Text = $probeText; ExitCode = $probeExitCode }
}
