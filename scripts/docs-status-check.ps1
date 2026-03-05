[CmdletBinding()]
param(
    [string]$ParityJsonPath = ".\release\parity-go-zig.json",
    [switch]$RefreshParity,
    [string]$GitHubToken = $env:GITHUB_TOKEN
)

$ErrorActionPreference = "Stop"

function Assert-Contains {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Token,
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][ref]$Failures
    )

    $text = Get-Content -Path $Path -Raw
    if (-not $text.Contains($Token)) {
        $Failures.Value += "$Path missing '$Label' token: $Token"
    }
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Push-Location $repoRoot
try {
    $parityScript = Join-Path $PSScriptRoot "check-go-method-parity.ps1"
    if ($RefreshParity -or -not (Test-Path $ParityJsonPath)) {
        if ($GitHubToken) {
            & $parityScript -OutputJsonPath $ParityJsonPath -GitHubToken $GitHubToken | Out-Host
        } else {
            & $parityScript -OutputJsonPath $ParityJsonPath | Out-Host
        }
    }

    if (-not (Test-Path $ParityJsonPath)) {
        throw "Parity report not found: $ParityJsonPath"
    }

    $report = Get-Content -Path $ParityJsonPath -Raw | ConvertFrom-Json
    $counts = $report.counts
    $goRef = $report.baseline.go.ref
    $originalRef = $report.baseline.original.ref
    $originalBetaRef = $report.baseline.originalBeta.ref

    $releaseTag = $null
    $releaseHeaders = @{
        "User-Agent" = "openclaw-zig-docs-status-check"
        "Accept" = "application/vnd.github+json"
    }
    if ($GitHubToken) {
        $releaseHeaders["Authorization"] = "Bearer $GitHubToken"
    }
    try {
        $release = Invoke-RestMethod -Headers $releaseHeaders -Uri "https://api.github.com/repos/adybag14-cyber/openclaw-zig-port/releases/latest"
        if ($null -ne $release -and -not [string]::IsNullOrWhiteSpace($release.tag_name)) {
            $releaseTag = [string]$release.tag_name
        }
    } catch {
        Write-Warning "Unable to resolve latest GitHub release tag via GitHub API. Release-tag docs checks will be skipped."
    }

    $failures = @()

    Assert-Contains -Path "README.md" -Token ('RPC method surface in Zig: `' + $counts.zig + '`') -Label "README zig method surface" -Failures ([ref]$failures)
    Assert-Contains -Path "README.md" -Token ('Go baseline (`' + $goRef + '`):') -Label "README go baseline ref" -Failures ([ref]$failures)
    Assert-Contains -Path "README.md" -Token ('Original OpenClaw baseline (`' + $originalRef + '`):') -Label "README original baseline ref" -Failures ([ref]$failures)
    Assert-Contains -Path "README.md" -Token ('Original OpenClaw beta baseline (`' + $originalBetaRef + '`):') -Label "README original beta baseline ref" -Failures ([ref]$failures)
    Assert-Contains -Path "README.md" -Token ('Union baseline: `' + $counts.union + '/' + $counts.union + '` covered (`MISSING_IN_ZIG=' + $counts.unionMissingInZig + '`)') -Label "README union parity token" -Failures ([ref]$failures)
    Assert-Contains -Path "README.md" -Token ('Gateway events: stable `' + $counts.originalEvents + '/' + $counts.originalEvents + '`, beta `' + $counts.originalBetaEvents + '/' + $counts.originalBetaEvents + '`, union `' + $counts.unionEvents + '/' + $counts.unionEvents + '` (`UNION_EVENTS_MISSING_IN_ZIG=' + $counts.unionEventsMissingInZig + '`)') -Label "README gateway events token" -Failures ([ref]$failures)

    Assert-Contains -Path "docs/index.md" -Token ('RPC surface in Zig: `' + $counts.zig + '` methods') -Label "docs/index zig method surface" -Failures ([ref]$failures)
    Assert-Contains -Path "docs/index.md" -Token ('Go baseline (`' + $goRef + '`): `' + $counts.go + '/' + $counts.go + '`') -Label "docs/index go baseline token" -Failures ([ref]$failures)
    Assert-Contains -Path "docs/index.md" -Token ('Original OpenClaw baseline (`' + $originalRef + '`): `' + $counts.original + '/' + $counts.original + '`') -Label "docs/index original baseline token" -Failures ([ref]$failures)
    Assert-Contains -Path "docs/index.md" -Token ('Original OpenClaw beta baseline (`' + $originalBetaRef + '`): `' + $counts.originalBeta + '/' + $counts.originalBeta + '`') -Label "docs/index original beta baseline token" -Failures ([ref]$failures)
    Assert-Contains -Path "docs/index.md" -Token ('Union baseline: `' + $counts.union + '/' + $counts.union + '` (`MISSING_IN_ZIG=' + $counts.unionMissingInZig + '`)') -Label "docs/index union token" -Failures ([ref]$failures)

    Assert-Contains -Path "docs/operations.md" -Token ('GO_MISSING_IN_ZIG=' + $counts.goMissingInZig) -Label "docs/operations go missing token" -Failures ([ref]$failures)
    Assert-Contains -Path "docs/operations.md" -Token ('ORIGINAL_MISSING_IN_ZIG=' + $counts.originalMissingInZig) -Label "docs/operations original missing token" -Failures ([ref]$failures)
    Assert-Contains -Path "docs/operations.md" -Token ('ORIGINAL_BETA_MISSING_IN_ZIG=' + $counts.originalBetaMissingInZig) -Label "docs/operations original beta missing token" -Failures ([ref]$failures)
    Assert-Contains -Path "docs/operations.md" -Token ('UNION_MISSING_IN_ZIG=' + $counts.unionMissingInZig) -Label "docs/operations union missing token" -Failures ([ref]$failures)
    Assert-Contains -Path "docs/operations.md" -Token ('UNION_EVENTS_MISSING_IN_ZIG=' + $counts.unionEventsMissingInZig) -Label "docs/operations union event missing token" -Failures ([ref]$failures)
    Assert-Contains -Path "docs/operations.md" -Token ('ZIG_COUNT=' + $counts.zig) -Label "docs/operations zig count token" -Failures ([ref]$failures)
    Assert-Contains -Path "docs/operations.md" -Token ('ZIG_EVENTS_COUNT=' + $counts.zigEvents) -Label "docs/operations zig events token" -Failures ([ref]$failures)

    if ($releaseTag) {
        Assert-Contains -Path "README.md" -Token ('Latest published edge release tag: `' + $releaseTag + '`') -Label "README release tag token" -Failures ([ref]$failures)
        Assert-Contains -Path "docs/index.md" -Token ('Latest published edge release tag: `' + $releaseTag + '`') -Label "docs/index release tag token" -Failures ([ref]$failures)
        Assert-Contains -Path "docs/operations.md" -Token ('Latest published edge release: `' + $releaseTag + '`') -Label "docs/operations release tag token" -Failures ([ref]$failures)
    }

    if ($failures.Count -gt 0) {
        Write-Host "Docs status drift detected:"
        foreach ($failure in $failures) {
            Write-Host " - $failure"
        }
        exit 1
    }

    Write-Host ("Docs status check passed. zig={0} union={1}/{1} events={2}/{2}" -f $counts.zig, $counts.union, $counts.unionEvents)
    if ($releaseTag) {
        Write-Host ("Release tag token check passed: {0}" -f $releaseTag)
    }
    $global:LASTEXITCODE = 0
} finally {
    Pop-Location
}
