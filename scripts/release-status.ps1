# SPDX-License-Identifier: GPL-2.0-only
[CmdletBinding()]
param(
    [string]$Repository = "adybag14-cyber/ZAR-Zig-Agent-Runtime",
    [string]$ReleaseTag,
    [string]$NpmPackageName = "@adybag14-cyber/openclaw-zig-rpc-client",
    [string]$PythonPackageName = "openclaw-zig-rpc-client",
    [string]$PackageRegistryStatusPath = "",
    [string]$OutputJsonPath = ".\release\release-status.json",
    [string]$OutputMarkdownPath = ".\release\release-status.md",
    [string]$GitHubToken = $env:GITHUB_TOKEN
)

$ErrorActionPreference = "Stop"

function Get-StatusCode {
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    if ($null -ne $ErrorRecord.Exception.Response) {
        try {
            if ($null -ne $ErrorRecord.Exception.Response.StatusCode) {
                return [int]$ErrorRecord.Exception.Response.StatusCode
            }
        } catch {
        }

        try {
            return [int]$ErrorRecord.Exception.Response.StatusCode.value__
        } catch {
        }
    }

    return $null
}

function Invoke-JsonRequest {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [hashtable]$Headers = @{}
    )

    try {
        $response = Invoke-RestMethod -Uri $Uri -Headers $Headers -Method Get
        return [pscustomobject]@{
            ok         = $true
            statusCode = 200
            body       = $response
            error      = $null
        }
    } catch {
        return [pscustomobject]@{
            ok         = $false
            statusCode = Get-StatusCode -ErrorRecord $_
            body       = $null
            error      = $_.Exception.Message
        }
    }
}

function Resolve-LatestEdgeReleaseTag {
    param(
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][hashtable]$Headers
    )

    $response = Invoke-JsonRequest -Uri "https://api.github.com/repos/$Repository/releases?per_page=20" -Headers $Headers
    if (-not $response.ok -or $null -eq $response.body) {
        return $null
    }

    foreach ($candidate in @($response.body)) {
        if ($candidate.draft) {
            continue
        }
        $tag = [string]$candidate.tag_name
        if (-not [string]::IsNullOrWhiteSpace($tag) -and $tag -match '^v\d+\.\d+\.\d+-zig-edge\.\d+$') {
            return $tag
        }
    }

    return $null
}

function Get-LatestWorkflowRunSnapshot {
    param(
        [Parameter(Mandatory = $true)]$Runs,
        [Parameter(Mandatory = $true)][string]$WorkflowName
    )

    $run = @($Runs | Where-Object { $_.name -eq $WorkflowName } | Select-Object -First 1)
    if ($run.Count -eq 0) {
        return [ordered]@{
            name        = $WorkflowName
            found       = $false
            runId       = $null
            status      = $null
            conclusion  = $null
            event       = $null
            headBranch  = $null
            headSha     = $null
            displayTitle = $null
            createdAt   = $null
            updatedAt   = $null
            url         = $null
        }
    }

    $selected = $run[0]
    return [ordered]@{
        name         = $WorkflowName
        found        = $true
        runId        = $selected.id
        status       = [string]$selected.status
        conclusion   = [string]$selected.conclusion
        event        = [string]$selected.event
        headBranch   = [string]$selected.head_branch
        headSha      = [string]$selected.head_sha
        displayTitle = [string]$selected.display_title
        createdAt    = [string]$selected.created_at
        updatedAt    = [string]$selected.updated_at
        url          = [string]$selected.html_url
    }
}

function Get-WorkflowConclusionSummary {
    param(
        [Parameter(Mandatory = $true)]$Workflow
    )

    if (-not $Workflow.found) {
        return "missing"
    }
    if ($Workflow.status -ne "completed") {
        return $Workflow.status
    }
    if ([string]::IsNullOrWhiteSpace($Workflow.conclusion)) {
        return "completed"
    }
    return $Workflow.conclusion
}

function Get-BlockerList {
    param(
        [System.Collections.Generic.List[string]]$List
    )

    if ($List.Count -eq 0) {
        return @("none")
    }
    return @($List)
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Push-Location $repoRoot
try {
    $headers = @{
        "User-Agent" = "openclaw-zig-release-status"
        "Accept"     = "application/vnd.github+json"
    }
    if ($GitHubToken) {
        $headers["Authorization"] = "Bearer $GitHubToken"
    }

    if ([string]::IsNullOrWhiteSpace($ReleaseTag)) {
        $ReleaseTag = Resolve-LatestEdgeReleaseTag -Repository $Repository -Headers $headers
    }

    $resolvedPackageRegistryStatusPath = $PackageRegistryStatusPath
    if ([string]::IsNullOrWhiteSpace($resolvedPackageRegistryStatusPath)) {
        $resolvedPackageRegistryStatusPath = Join-Path ([System.IO.Path]::GetTempPath()) ("openclaw-zig-package-registry-status-{0}.json" -f ([guid]::NewGuid().ToString("N")))
    }

    if (-not (Test-Path -LiteralPath $resolvedPackageRegistryStatusPath)) {
        $packageRegistryScript = Join-Path $PSScriptRoot "package-registry-status.ps1"
        if (-not (Test-Path -LiteralPath $packageRegistryScript)) {
            throw "Package registry status script not found: $packageRegistryScript"
        }

        $packageArgs = @{
            Repository         = $Repository
            ReleaseTag         = $ReleaseTag
            NpmPackageName     = $NpmPackageName
            PythonPackageName  = $PythonPackageName
            OutputJsonPath     = $resolvedPackageRegistryStatusPath
        }
        if (-not [string]::IsNullOrWhiteSpace($GitHubToken)) {
            $packageArgs.GitHubToken = $GitHubToken
        }

        & $packageRegistryScript @packageArgs
        if ($LASTEXITCODE -ne 0) {
            throw "Package registry status generation failed with exit code $LASTEXITCODE"
        }
    }

    if (-not (Test-Path -LiteralPath $resolvedPackageRegistryStatusPath)) {
        throw "Package registry status report not found: $resolvedPackageRegistryStatusPath"
    }

    $packageReport = Get-Content -LiteralPath $resolvedPackageRegistryStatusPath -Raw | ConvertFrom-Json
    if ([string]::IsNullOrWhiteSpace($ReleaseTag) -and -not [string]::IsNullOrWhiteSpace($packageReport.release.tag)) {
        $ReleaseTag = [string]$packageReport.release.tag
    }

    $runsResponse = Invoke-JsonRequest -Uri "https://api.github.com/repos/$Repository/actions/runs?per_page=100" -Headers $headers
    $workflowRuns = @()
    if ($runsResponse.ok -and $null -ne $runsResponse.body -and $null -ne $runsResponse.body.workflow_runs) {
        $workflowRuns = @($runsResponse.body.workflow_runs)
    }

    $workflowSnapshots = [ordered]@{
        zigCi          = Get-LatestWorkflowRunSnapshot -Runs $workflowRuns -WorkflowName "zig-ci"
        docsPages      = Get-LatestWorkflowRunSnapshot -Runs $workflowRuns -WorkflowName "docs-pages"
        releasePreview = Get-LatestWorkflowRunSnapshot -Runs $workflowRuns -WorkflowName "release-preview"
        npmRelease     = Get-LatestWorkflowRunSnapshot -Runs $workflowRuns -WorkflowName "npm-release"
        pythonRelease  = Get-LatestWorkflowRunSnapshot -Runs $workflowRuns -WorkflowName "python-release"
    }

    $edgeBlockers = [System.Collections.Generic.List[string]]::new()
    $publicRegistryBlockers = [System.Collections.Generic.List[string]]::new()

    if ((Get-WorkflowConclusionSummary -Workflow $workflowSnapshots.zigCi) -ne "success") {
        $edgeBlockers.Add("latest zig-ci run is not green") | Out-Null
    }
    if ((Get-WorkflowConclusionSummary -Workflow $workflowSnapshots.docsPages) -ne "success") {
        $edgeBlockers.Add("latest docs-pages run is not green") | Out-Null
    }
    if (-not $packageReport.release.exists) {
        $edgeBlockers.Add("release tag is not published on GitHub yet") | Out-Null
    } elseif (-not $packageReport.summary.releaseAssetsReady) {
        $edgeBlockers.Add("release tag exists without published assets") | Out-Null
    }
    if ($packageReport.release.exists -and -not $packageReport.summary.uvxFallbackReady) {
        $edgeBlockers.Add("python fallback artifacts are missing from the GitHub release") | Out-Null
    }

    if (-not $packageReport.summary.publicNpmVersionLive) {
        $publicRegistryBlockers.Add("npmjs version is not live") | Out-Null
    }
    if (-not $packageReport.summary.publicPypiVersionLive) {
        $publicRegistryBlockers.Add("PyPI version is not live") | Out-Null
    }

    $report = [ordered]@{
        repository  = $Repository
        generatedAt = (Get-Date).ToUniversalTime().ToString("o")
        release     = [ordered]@{
            tag             = $ReleaseTag
            published       = [bool]$packageReport.release.exists
            assetsReady     = [bool]$packageReport.summary.releaseAssetsReady
            assetCount      = $packageReport.release.assetCount
            packageFallback = [ordered]@{
                uvxReady = [bool]$packageReport.summary.uvxFallbackReady
            }
        }
        packageStatus = [ordered]@{
            npm  = $packageReport.npm
            pypi = $packageReport.pypi
        }
        workflows   = $workflowSnapshots
        summary     = [ordered]@{
            latestValidationGreen     = ((Get-WorkflowConclusionSummary -Workflow $workflowSnapshots.zigCi) -eq "success" -and (Get-WorkflowConclusionSummary -Workflow $workflowSnapshots.docsPages) -eq "success")
            publicNpmVersionLive      = [bool]$packageReport.summary.publicNpmVersionLive
            publicPypiVersionLive     = [bool]$packageReport.summary.publicPypiVersionLive
            edgeReleasePublished      = [bool]$packageReport.release.exists
            edgeReleaseAssetsReady    = [bool]$packageReport.summary.releaseAssetsReady
            uvxFallbackReady          = [bool]$packageReport.summary.uvxFallbackReady
            edgeReleaseBlockers       = Get-BlockerList -List $edgeBlockers
            publicRegistryBlockers    = Get-BlockerList -List $publicRegistryBlockers
            actionsApiStatusCode      = $runsResponse.statusCode
            actionsApiError           = $runsResponse.error
        }
    }

    $outputDirectory = Split-Path -Parent $OutputJsonPath
    if ($outputDirectory) {
        New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    }
    $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputJsonPath -Encoding utf8

    $markdownLines = New-Object System.Collections.Generic.List[string]
    $markdownLines.Add("# Release Status") | Out-Null
    $markdownLines.Add("") | Out-Null
    $markdownLines.Add("- Repository: ``$Repository``") | Out-Null
    $markdownLines.Add("- Generated at: ``$($report.generatedAt)``") | Out-Null
    if (-not [string]::IsNullOrWhiteSpace($ReleaseTag)) {
        $markdownLines.Add("- Release tag: ``$ReleaseTag``") | Out-Null
    }
    $markdownLines.Add("- Release published: ``$($report.release.published)``") | Out-Null
    $markdownLines.Add("- Release assets ready: ``$($report.release.assetsReady)``") | Out-Null
    $markdownLines.Add("- uvx fallback ready: ``$($report.release.packageFallback.uvxReady)``") | Out-Null
    $markdownLines.Add("- Public npm live: ``$($report.summary.publicNpmVersionLive)``") | Out-Null
    $markdownLines.Add("- Public PyPI live: ``$($report.summary.publicPypiVersionLive)``") | Out-Null
    $markdownLines.Add("") | Out-Null
    $markdownLines.Add("## Workflows") | Out-Null
    $markdownLines.Add("") | Out-Null

    foreach ($workflowName in @("zigCi", "docsPages", "releasePreview", "npmRelease", "pythonRelease")) {
        $workflow = $report.workflows.$workflowName
        $state = Get-WorkflowConclusionSummary -Workflow $workflow
        $line = "- ``$($workflow.name)``: ``$state``"
        if ($workflow.runId) {
            $line += " ($($workflow.runId))"
        }
        if (-not [string]::IsNullOrWhiteSpace($workflow.displayTitle)) {
            $line += " - $($workflow.displayTitle)"
        }
        if (-not [string]::IsNullOrWhiteSpace($workflow.url)) {
            $line += " - $($workflow.url)"
        }
        $markdownLines.Add($line) | Out-Null
    }

    $markdownLines.Add("") | Out-Null
    $markdownLines.Add("## Edge Release Blockers") | Out-Null
    $markdownLines.Add("") | Out-Null
    foreach ($blocker in @($report.summary.edgeReleaseBlockers)) {
        $markdownLines.Add("- $blocker") | Out-Null
    }

    $markdownLines.Add("") | Out-Null
    $markdownLines.Add("## Public Registry Blockers") | Out-Null
    $markdownLines.Add("") | Out-Null
    foreach ($blocker in @($report.summary.publicRegistryBlockers)) {
        $markdownLines.Add("- $blocker") | Out-Null
    }

    $markdownOutputDirectory = Split-Path -Parent $OutputMarkdownPath
    if ($markdownOutputDirectory) {
        New-Item -ItemType Directory -Path $markdownOutputDirectory -Force | Out-Null
    }
    Set-Content -LiteralPath $OutputMarkdownPath -Value $markdownLines -Encoding utf8

    Write-Host ("Release status generated: {0}" -f (Resolve-Path $OutputJsonPath))
    Write-Host ("Release status markdown generated: {0}" -f (Resolve-Path $OutputMarkdownPath))
    Write-Host ("Edge blockers: {0}" -f (($report.summary.edgeReleaseBlockers -join "; ")))
    Write-Host ("Public registry blockers: {0}" -f (($report.summary.publicRegistryBlockers -join "; ")))
    $global:LASTEXITCODE = 0
} finally {
    Pop-Location
}
