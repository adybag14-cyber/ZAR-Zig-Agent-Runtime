param(
    [string] $GoRegistryPath = "",
    [string] $GoRegistryUrl = "",
    [string] $GoRepo = "adybag14-cyber/openclaw-go-port",
    [string] $GoTag = "",
    [string] $OriginalMethodsPath = "",
    [string] $OriginalMethodsUrl = "",
    [string] $OriginalRepo = "openclaw/openclaw",
    [string] $OriginalRef = "",
    [string] $OriginalMethodsRelativePath = "src/gateway/server-methods-list.ts",
    [string] $OriginalEventsPath = "",
    [string] $OriginalEventsUrl = "",
    [string] $OriginalEventsRelativePath = "src/gateway/events.ts",
    [string] $OriginalBetaMethodsPath = "",
    [string] $OriginalBetaMethodsUrl = "",
    [string] $OriginalBetaRepo = "openclaw/openclaw",
    [string] $OriginalBetaRef = "",
    [string] $OriginalBetaMethodsRelativePath = "src/gateway/server-methods-list.ts",
    [string] $OriginalBetaEventsPath = "",
    [string] $OriginalBetaEventsUrl = "",
    [string] $OriginalBetaEventsRelativePath = "src/gateway/events.ts",
    [string] $ZigRegistryPath = "",
    [string] $OutputJsonPath = "",
    [string] $OutputMarkdownPath = "",
    [string] $GitHubToken = "",
    [switch] $NoOriginalBetaBaseline,
    [switch] $FailOnExtra
)

$ErrorActionPreference = "Stop"
$ApiHeaders = @{
    "User-Agent" = "openclaw-zig-port-parity"
    "Accept" = "application/vnd.github+json"
}
if ([string]::IsNullOrWhiteSpace($GitHubToken)) {
    $GitHubToken = $env:GITHUB_TOKEN
}
if (-not [string]::IsNullOrWhiteSpace($GitHubToken)) {
    $ApiHeaders["Authorization"] = "Bearer $GitHubToken"
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if ([string]::IsNullOrWhiteSpace($ZigRegistryPath)) {
    $ZigRegistryPath = Join-Path $repoRoot "src\gateway\registry.zig"
}

function Read-ContentChecked {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    if (-not (Test-Path $Path)) {
        throw "File not found: $Path"
    }
    return Get-Content -Raw -Path $Path
}

function Fetch-Text {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Url
    )

    try {
        return (Invoke-WebRequest -UseBasicParsing -Headers $ApiHeaders -Uri $Url).Content
    }
    catch {
        throw "Failed to fetch URL: $Url`n$($_.Exception.Message)"
    }
}

function Resolve-LatestReleaseTag {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Repo
    )

    $releaseUrl = "https://api.github.com/repos/$Repo/releases/latest"
    try {
        $release = Invoke-RestMethod -Headers $ApiHeaders -Uri $releaseUrl
        if ($null -ne $release -and -not [string]::IsNullOrWhiteSpace($release.tag_name)) {
            return [string] $release.tag_name
        }
    }
    catch {
        Write-Warning "Failed to resolve latest release for $Repo via ${releaseUrl}: $($_.Exception.Message)"
    }

    $tagsUrl = "https://api.github.com/repos/$Repo/tags?per_page=1"
    try {
        $tags = Invoke-RestMethod -Headers $ApiHeaders -Uri $tagsUrl
        if ($null -ne $tags -and $tags.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($tags[0].name)) {
            return [string] $tags[0].name
        }
    }
    catch {
        throw "Failed to resolve tags for $Repo via $tagsUrl`n$($_.Exception.Message)"
    }

    throw "Could not resolve latest release/tag for repository: $Repo"
}

function Resolve-LatestPreReleaseTag {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Repo
    )

    $releasesUrl = "https://api.github.com/repos/$Repo/releases?per_page=100"
    try {
        $releases = Invoke-RestMethod -Headers $ApiHeaders -Uri $releasesUrl
        if ($null -eq $releases) {
            throw "No release payload returned."
        }

        foreach ($release in $releases) {
            if ($release.draft -eq $true) {
                continue
            }
            if ($release.prerelease -eq $true -and -not [string]::IsNullOrWhiteSpace($release.tag_name)) {
                return [string] $release.tag_name
            }
        }
    }
    catch {
        throw "Failed to resolve prereleases for $Repo via ${releasesUrl}`n$($_.Exception.Message)"
    }

    throw "Could not resolve latest prerelease tag for repository: $Repo"
}

function Resolve-GoRegistry {
    param(
        [string] $Path,
        [string] $Url,
        [string] $Repo,
        [string] $Tag
    )

    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        return [ordered]@{
            source = Read-ContentChecked -Path $Path
            origin = "path"
            path = $Path
            url = $null
            repo = $null
            ref = $null
        }
    }

    if ([string]::IsNullOrWhiteSpace($Url)) {
        $resolvedTag = if ([string]::IsNullOrWhiteSpace($Tag)) { Resolve-LatestReleaseTag -Repo $Repo } else { $Tag }
        $Url = "https://raw.githubusercontent.com/$Repo/$resolvedTag/go-agent/internal/rpc/registry.go"
        $Tag = $resolvedTag
    }

    return [ordered]@{
        source = Fetch-Text -Url $Url
        origin = if ([string]::IsNullOrWhiteSpace($Tag)) { "url" } else { "latest_release" }
        path = $null
        url = $Url
        repo = if ([string]::IsNullOrWhiteSpace($Tag)) { $null } else { $Repo }
        ref = $Tag
    }
}

function Resolve-OriginalMethods {
    param(
        [string] $Path,
        [string] $Url,
        [string] $Repo,
        [string] $Ref,
        [string] $RelativePath
    )

    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        return [ordered]@{
            source = Read-ContentChecked -Path $Path
            origin = "path"
            path = $Path
            url = $null
            repo = $null
            ref = $null
        }
    }

    if ([string]::IsNullOrWhiteSpace($Url)) {
        $resolvedRef = if ([string]::IsNullOrWhiteSpace($Ref)) { Resolve-LatestReleaseTag -Repo $Repo } else { $Ref }
        $Url = "https://raw.githubusercontent.com/$Repo/$resolvedRef/$RelativePath"
        $Ref = $resolvedRef
    }

    return [ordered]@{
        source = Fetch-Text -Url $Url
        origin = if ([string]::IsNullOrWhiteSpace($Ref)) { "url" } else { "latest_release_or_ref" }
        path = $null
        url = $Url
        repo = if ([string]::IsNullOrWhiteSpace($Ref)) { $null } else { $Repo }
        ref = $Ref
    }
}

function Resolve-OriginalBetaMethods {
    param(
        [string] $Path,
        [string] $Url,
        [string] $Repo,
        [string] $Ref,
        [string] $RelativePath
    )

    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        return [ordered]@{
            source = Read-ContentChecked -Path $Path
            origin = "path"
            path = $Path
            url = $null
            repo = $null
            ref = $null
        }
    }

    if ([string]::IsNullOrWhiteSpace($Url)) {
        $resolvedRef = if ([string]::IsNullOrWhiteSpace($Ref)) { Resolve-LatestPreReleaseTag -Repo $Repo } else { $Ref }
        $Url = "https://raw.githubusercontent.com/$Repo/$resolvedRef/$RelativePath"
        $Ref = $resolvedRef
    }

    return [ordered]@{
        source = Fetch-Text -Url $Url
        origin = if ([string]::IsNullOrWhiteSpace($Ref)) { "url" } else { "latest_prerelease_or_ref" }
        path = $null
        url = $Url
        repo = if ([string]::IsNullOrWhiteSpace($Ref)) { $null } else { $Repo }
        ref = $Ref
        relativePath = $RelativePath
    }
}

function Resolve-OriginalEvents {
    param(
        [string] $Path,
        [string] $Url,
        [string] $Repo,
        [string] $Ref,
        [string] $RelativePath
    )

    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        return [ordered]@{
            source = Read-ContentChecked -Path $Path
            origin = "path"
            path = $Path
            url = $null
            repo = $null
            ref = $null
            relativePath = $RelativePath
        }
    }

    if ([string]::IsNullOrWhiteSpace($Url)) {
        $resolvedRef = if ([string]::IsNullOrWhiteSpace($Ref)) { Resolve-LatestReleaseTag -Repo $Repo } else { $Ref }
        $Url = "https://raw.githubusercontent.com/$Repo/$resolvedRef/$RelativePath"
        $Ref = $resolvedRef
    }

    return [ordered]@{
        source = Fetch-Text -Url $Url
        origin = if ([string]::IsNullOrWhiteSpace($Ref)) { "url" } else { "latest_release_or_ref" }
        path = $null
        url = $Url
        repo = if ([string]::IsNullOrWhiteSpace($Ref)) { $null } else { $Repo }
        ref = $Ref
        relativePath = $RelativePath
    }
}

function Resolve-OriginalBetaEvents {
    param(
        [string] $Path,
        [string] $Url,
        [string] $Repo,
        [string] $Ref,
        [string] $RelativePath
    )

    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        return [ordered]@{
            source = Read-ContentChecked -Path $Path
            origin = "path"
            path = $Path
            url = $null
            repo = $null
            ref = $null
            relativePath = $RelativePath
        }
    }

    if ([string]::IsNullOrWhiteSpace($Url)) {
        $resolvedRef = if ([string]::IsNullOrWhiteSpace($Ref)) { Resolve-LatestPreReleaseTag -Repo $Repo } else { $Ref }
        $Url = "https://raw.githubusercontent.com/$Repo/$resolvedRef/$RelativePath"
        $Ref = $resolvedRef
    }

    return [ordered]@{
        source = Fetch-Text -Url $Url
        origin = if ([string]::IsNullOrWhiteSpace($Ref)) { "url" } else { "latest_prerelease_or_ref" }
        path = $null
        url = $Url
        repo = if ([string]::IsNullOrWhiteSpace($Ref)) { $null } else { $Repo }
        ref = $Ref
        relativePath = $RelativePath
    }
}

function Extract-GoMethods {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Source
    )

    $pattern = "var\s+defaultSupportedRPCMethods\s*=\s*\[\]string\s*\{(?<body>[\s\S]*?)\n\}"
    $match = [regex]::Match($Source, $pattern)
    if (-not $match.Success) {
        throw "Could not locate defaultSupportedRPCMethods block in Go source."
    }

    $methods = @()
    foreach ($m in [regex]::Matches($match.Groups["body"].Value, '"([^"]+)"')) {
        $methods += $m.Groups[1].Value.Trim().ToLowerInvariant()
    }

    if ($methods.Count -eq 0) {
        throw "Extracted zero methods from Go source."
    }

    return $methods | Sort-Object -Unique
}

function Extract-OriginalMethods {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Source
    )

    $pattern = "const\s+BASE_METHODS\s*=\s*\[(?<body>[\s\S]*?)\n\];"
    $match = [regex]::Match($Source, $pattern)
    if (-not $match.Success) {
        throw "Could not locate BASE_METHODS block in original OpenClaw source."
    }

    $methods = @()
    foreach ($m in [regex]::Matches($match.Groups["body"].Value, '"([^"]+)"')) {
        $methods += $m.Groups[1].Value.Trim().ToLowerInvariant()
    }

    if ($methods.Count -eq 0) {
        throw "Extracted zero methods from original OpenClaw source."
    }

    return $methods | Sort-Object -Unique
}

function Extract-OriginalGatewayEvents {
    param(
        [Parameter(Mandatory = $true)]
        [string] $MethodsSource,
        [Parameter(Mandatory = $true)]
        [string] $EventsSource
    )

    $pattern = "export\s+const\s+GATEWAY_EVENTS\s*=\s*\[(?<body>[\s\S]*?)\n\];"
    $match = [regex]::Match($MethodsSource, $pattern)
    if (-not $match.Success) {
        throw "Could not locate GATEWAY_EVENTS block in original OpenClaw methods source."
    }

    $events = @()
    foreach ($m in [regex]::Matches($match.Groups["body"].Value, '"([^"]+)"')) {
        $events += $m.Groups[1].Value.Trim().ToLowerInvariant()
    }

    if ($match.Groups["body"].Value -match "\bGATEWAY_EVENT_UPDATE_AVAILABLE\b") {
        $updatePattern = "GATEWAY_EVENT_UPDATE_AVAILABLE\s*=\s*""([^""]+)"""
        $updateMatch = [regex]::Match($EventsSource, $updatePattern)
        if ($updateMatch.Success) {
            $events += $updateMatch.Groups[1].Value.Trim().ToLowerInvariant()
        }
        else {
            throw "Could not resolve GATEWAY_EVENT_UPDATE_AVAILABLE constant from events source."
        }
    }

    if ($events.Count -eq 0) {
        throw "Extracted zero gateway events from original OpenClaw source."
    }

    return $events | Sort-Object -Unique
}

function Extract-ZigMethods {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Source
    )

    $pattern = "pub\s+const\s+supported_methods\s*=\s*\[_\]\[\]const\s+u8\s*\{(?<body>[\s\S]*?)\n\};"
    $match = [regex]::Match($Source, $pattern)
    if (-not $match.Success) {
        throw "Could not locate supported_methods block in Zig source."
    }

    $methods = @()
    foreach ($m in [regex]::Matches($match.Groups["body"].Value, '"([^"]+)"')) {
        $methods += $m.Groups[1].Value.Trim().ToLowerInvariant()
    }

    if ($methods.Count -eq 0) {
        throw "Extracted zero methods from Zig source."
    }

    return $methods | Sort-Object -Unique
}

function Extract-ZigEvents {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Source
    )

    $pattern = "pub\s+const\s+supported_events\s*=\s*\[_\]\[\]const\s+u8\s*\{(?<body>[\s\S]*?)\n\};"
    $match = [regex]::Match($Source, $pattern)
    if (-not $match.Success) {
        throw "Could not locate supported_events block in Zig source."
    }

    $events = @()
    foreach ($m in [regex]::Matches($match.Groups["body"].Value, '"([^"]+)"')) {
        $events += $m.Groups[1].Value.Trim().ToLowerInvariant()
    }

    if ($events.Count -eq 0) {
        throw "Extracted zero events from Zig source."
    }

    return $events | Sort-Object -Unique
}

function New-MethodSet {
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $Methods
    )

    $set = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($m in $Methods) {
        [void] $set.Add($m)
    }
    return $set
}

function Compare-BaselineToZig {
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $BaselineMethods,
        [Parameter(Mandatory = $true)]
        [string[]] $ZigMethods
    )

    $baselineSet = New-MethodSet -Methods $BaselineMethods
    $zigSet = New-MethodSet -Methods $ZigMethods

    $missingInZig = New-Object System.Collections.Generic.List[string]
    foreach ($m in $BaselineMethods) {
        if (-not $zigSet.Contains($m)) {
            $missingInZig.Add($m) | Out-Null
        }
    }

    $extraInZig = New-Object System.Collections.Generic.List[string]
    foreach ($m in $ZigMethods) {
        if (-not $baselineSet.Contains($m)) {
            $extraInZig.Add($m) | Out-Null
        }
    }

    return [ordered]@{
        missingInZig = @($missingInZig | Sort-Object)
        extraInZig = @($extraInZig | Sort-Object)
    }
}

$goRegistry = Resolve-GoRegistry -Path $GoRegistryPath -Url $GoRegistryUrl -Repo $GoRepo -Tag $GoTag
$originalMethods = Resolve-OriginalMethods -Path $OriginalMethodsPath -Url $OriginalMethodsUrl -Repo $OriginalRepo -Ref $OriginalRef -RelativePath $OriginalMethodsRelativePath
$originalEvents = Resolve-OriginalEvents -Path $OriginalEventsPath -Url $OriginalEventsUrl -Repo $OriginalRepo -Ref $OriginalRef -RelativePath $OriginalEventsRelativePath
$originalBetaMethods = $null
$originalBetaEvents = $null
if (-not $NoOriginalBetaBaseline) {
    $originalBetaMethods = Resolve-OriginalBetaMethods -Path $OriginalBetaMethodsPath -Url $OriginalBetaMethodsUrl -Repo $OriginalBetaRepo -Ref $OriginalBetaRef -RelativePath $OriginalBetaMethodsRelativePath
    $originalBetaEvents = Resolve-OriginalBetaEvents -Path $OriginalBetaEventsPath -Url $OriginalBetaEventsUrl -Repo $OriginalBetaRepo -Ref $OriginalBetaRef -RelativePath $OriginalBetaEventsRelativePath
}
$zigSource = Read-ContentChecked -Path $ZigRegistryPath

$goMethods = Extract-GoMethods -Source $goRegistry.source
$originalMethodSet = Extract-OriginalMethods -Source $originalMethods.source
$originalEventSet = Extract-OriginalGatewayEvents -MethodsSource $originalMethods.source -EventsSource $originalEvents.source
$originalBetaMethodSet = @()
$originalBetaEventSet = @()
if ($null -ne $originalBetaMethods) {
    $originalBetaMethodSet = Extract-OriginalMethods -Source $originalBetaMethods.source
    $originalBetaEventSet = Extract-OriginalGatewayEvents -MethodsSource $originalBetaMethods.source -EventsSource $originalBetaEvents.source
}
$zigMethods = Extract-ZigMethods -Source $zigSource
$zigEvents = Extract-ZigEvents -Source $zigSource

$goVsZig = Compare-BaselineToZig -BaselineMethods $goMethods -ZigMethods $zigMethods
$originalVsZig = Compare-BaselineToZig -BaselineMethods $originalMethodSet -ZigMethods $zigMethods
$originalBetaVsZig = [ordered]@{
    missingInZig = @()
    extraInZig = @()
}
if ($originalBetaMethodSet.Count -gt 0) {
    $originalBetaVsZig = Compare-BaselineToZig -BaselineMethods $originalBetaMethodSet -ZigMethods $zigMethods
}

$unionSources = @($goMethods + $originalMethodSet)
if ($originalBetaMethodSet.Count -gt 0) {
    $unionSources += $originalBetaMethodSet
}
$unionBaselineMethods = @($unionSources | Sort-Object -Unique)
$unionVsZig = Compare-BaselineToZig -BaselineMethods $unionBaselineMethods -ZigMethods $zigMethods

$originalEventsVsZig = Compare-BaselineToZig -BaselineMethods $originalEventSet -ZigMethods $zigEvents
$originalBetaEventsVsZig = [ordered]@{
    missingInZig = @()
    extraInZig = @()
}
if ($originalBetaEventSet.Count -gt 0) {
    $originalBetaEventsVsZig = Compare-BaselineToZig -BaselineMethods $originalBetaEventSet -ZigMethods $zigEvents
}
$unionEventSources = @($originalEventSet)
if ($originalBetaEventSet.Count -gt 0) {
    $unionEventSources += $originalBetaEventSet
}
$unionBaselineEvents = @($unionEventSources | Sort-Object -Unique)
$unionEventsVsZig = Compare-BaselineToZig -BaselineMethods $unionBaselineEvents -ZigMethods $zigEvents

$originalBetaBaselineReport = [ordered]@{
    enabled = $false
    origin = $null
    path = $null
    url = $null
    eventsPath = $null
    eventsUrl = $null
    repo = $null
    ref = $null
    relativePath = $null
    eventsRelativePath = $null
}
if ($null -ne $originalBetaMethods) {
    $originalBetaBaselineReport = [ordered]@{
        enabled = $true
        origin = $originalBetaMethods.origin
        path = $originalBetaMethods.path
        url = $originalBetaMethods.url
        eventsPath = $originalBetaEvents.path
        eventsUrl = $originalBetaEvents.url
        repo = $originalBetaMethods.repo
        ref = $originalBetaMethods.ref
        relativePath = $OriginalBetaMethodsRelativePath
        eventsRelativePath = $OriginalBetaEventsRelativePath
    }
}

$report = [ordered]@{
    baseline = [ordered]@{
        go = [ordered]@{
            origin = $goRegistry.origin
            path = $goRegistry.path
            url = $goRegistry.url
            repo = $goRegistry.repo
            ref = $goRegistry.ref
        }
        original = [ordered]@{
            origin = $originalMethods.origin
            path = $originalMethods.path
            url = $originalMethods.url
            eventsPath = $originalEvents.path
            eventsUrl = $originalEvents.url
            repo = $originalMethods.repo
            ref = $originalMethods.ref
            relativePath = $OriginalMethodsRelativePath
            eventsRelativePath = $OriginalEventsRelativePath
        }
        originalBeta = $originalBetaBaselineReport
        zig = [ordered]@{
            path = $ZigRegistryPath
        }
    }
    counts = [ordered]@{
        go = $goMethods.Count
        original = $originalMethodSet.Count
        originalBeta = $originalBetaMethodSet.Count
        union = $unionBaselineMethods.Count
        zig = $zigMethods.Count
        goMissingInZig = $goVsZig.missingInZig.Count
        originalMissingInZig = $originalVsZig.missingInZig.Count
        originalBetaMissingInZig = $originalBetaVsZig.missingInZig.Count
        unionMissingInZig = $unionVsZig.missingInZig.Count
        goExtraInZig = $goVsZig.extraInZig.Count
        originalExtraInZig = $originalVsZig.extraInZig.Count
        originalBetaExtraInZig = $originalBetaVsZig.extraInZig.Count
        unionExtraInZig = $unionVsZig.extraInZig.Count
        originalEvents = $originalEventSet.Count
        originalBetaEvents = $originalBetaEventSet.Count
        unionEvents = $unionBaselineEvents.Count
        zigEvents = $zigEvents.Count
        originalEventsMissingInZig = $originalEventsVsZig.missingInZig.Count
        originalBetaEventsMissingInZig = $originalBetaEventsVsZig.missingInZig.Count
        unionEventsMissingInZig = $unionEventsVsZig.missingInZig.Count
        originalEventsExtraInZig = $originalEventsVsZig.extraInZig.Count
        originalBetaEventsExtraInZig = $originalBetaEventsVsZig.extraInZig.Count
        unionEventsExtraInZig = $unionEventsVsZig.extraInZig.Count
    }
    methods = [ordered]@{
        missingInZig = [ordered]@{
            go = $goVsZig.missingInZig
            original = $originalVsZig.missingInZig
            originalBeta = $originalBetaVsZig.missingInZig
            union = $unionVsZig.missingInZig
        }
        extraInZig = [ordered]@{
            go = $goVsZig.extraInZig
            original = $originalVsZig.extraInZig
            originalBeta = $originalBetaVsZig.extraInZig
            union = $unionVsZig.extraInZig
        }
    }
    events = [ordered]@{
        missingInZig = [ordered]@{
            original = $originalEventsVsZig.missingInZig
            originalBeta = $originalBetaEventsVsZig.missingInZig
            union = $unionEventsVsZig.missingInZig
        }
        extraInZig = [ordered]@{
            original = $originalEventsVsZig.extraInZig
            originalBeta = $originalBetaEventsVsZig.extraInZig
            union = $unionEventsVsZig.extraInZig
        }
    }
}

if (-not [string]::IsNullOrWhiteSpace($goRegistry.ref)) {
    Write-Output "GO_BASELINE_REF=$($goRegistry.ref)"
}
if (-not [string]::IsNullOrWhiteSpace($originalMethods.ref)) {
    Write-Output "ORIGINAL_BASELINE_REF=$($originalMethods.ref)"
}
if ($null -ne $originalBetaMethods -and -not [string]::IsNullOrWhiteSpace($originalBetaMethods.ref)) {
    Write-Output "ORIGINAL_BETA_BASELINE_REF=$($originalBetaMethods.ref)"
}
Write-Output "GO_COUNT=$($goMethods.Count)"
Write-Output "ORIGINAL_COUNT=$($originalMethodSet.Count)"
Write-Output "ORIGINAL_BETA_COUNT=$($originalBetaMethodSet.Count)"
Write-Output "UNION_BASELINE_COUNT=$($unionBaselineMethods.Count)"
Write-Output "ZIG_COUNT=$($zigMethods.Count)"
Write-Output "ORIGINAL_EVENTS_COUNT=$($originalEventSet.Count)"
Write-Output "ORIGINAL_BETA_EVENTS_COUNT=$($originalBetaEventSet.Count)"
Write-Output "UNION_EVENTS_BASELINE_COUNT=$($unionBaselineEvents.Count)"
Write-Output "ZIG_EVENTS_COUNT=$($zigEvents.Count)"

# Backward-compatible names for existing automation map to Go baseline.
Write-Output "MISSING_IN_ZIG=$($goVsZig.missingInZig.Count)"
Write-Output "EXTRA_IN_ZIG=$($goVsZig.extraInZig.Count)"

Write-Output "GO_MISSING_IN_ZIG=$($goVsZig.missingInZig.Count)"
if ($goVsZig.missingInZig.Count -gt 0) {
    Write-Output "GO_MISSING_METHODS_START"
    $goVsZig.missingInZig | Sort-Object | ForEach-Object { Write-Output $_ }
    Write-Output "GO_MISSING_METHODS_END"
}
Write-Output "GO_EXTRA_IN_ZIG=$($goVsZig.extraInZig.Count)"
if ($goVsZig.extraInZig.Count -gt 0) {
    Write-Output "GO_EXTRA_METHODS_START"
    $goVsZig.extraInZig | Sort-Object | ForEach-Object { Write-Output $_ }
    Write-Output "GO_EXTRA_METHODS_END"
}

Write-Output "ORIGINAL_MISSING_IN_ZIG=$($originalVsZig.missingInZig.Count)"
if ($originalVsZig.missingInZig.Count -gt 0) {
    Write-Output "ORIGINAL_MISSING_METHODS_START"
    $originalVsZig.missingInZig | Sort-Object | ForEach-Object { Write-Output $_ }
    Write-Output "ORIGINAL_MISSING_METHODS_END"
}
Write-Output "ORIGINAL_EXTRA_IN_ZIG=$($originalVsZig.extraInZig.Count)"

Write-Output "ORIGINAL_BETA_MISSING_IN_ZIG=$($originalBetaVsZig.missingInZig.Count)"
if ($originalBetaVsZig.missingInZig.Count -gt 0) {
    Write-Output "ORIGINAL_BETA_MISSING_METHODS_START"
    $originalBetaVsZig.missingInZig | Sort-Object | ForEach-Object { Write-Output $_ }
    Write-Output "ORIGINAL_BETA_MISSING_METHODS_END"
}
Write-Output "ORIGINAL_BETA_EXTRA_IN_ZIG=$($originalBetaVsZig.extraInZig.Count)"

Write-Output "ORIGINAL_EVENTS_MISSING_IN_ZIG=$($originalEventsVsZig.missingInZig.Count)"
if ($originalEventsVsZig.missingInZig.Count -gt 0) {
    Write-Output "ORIGINAL_EVENTS_MISSING_LIST_START"
    $originalEventsVsZig.missingInZig | Sort-Object | ForEach-Object { Write-Output $_ }
    Write-Output "ORIGINAL_EVENTS_MISSING_LIST_END"
}
Write-Output "ORIGINAL_EVENTS_EXTRA_IN_ZIG=$($originalEventsVsZig.extraInZig.Count)"

Write-Output "ORIGINAL_BETA_EVENTS_MISSING_IN_ZIG=$($originalBetaEventsVsZig.missingInZig.Count)"
if ($originalBetaEventsVsZig.missingInZig.Count -gt 0) {
    Write-Output "ORIGINAL_BETA_EVENTS_MISSING_LIST_START"
    $originalBetaEventsVsZig.missingInZig | Sort-Object | ForEach-Object { Write-Output $_ }
    Write-Output "ORIGINAL_BETA_EVENTS_MISSING_LIST_END"
}
Write-Output "ORIGINAL_BETA_EVENTS_EXTRA_IN_ZIG=$($originalBetaEventsVsZig.extraInZig.Count)"

Write-Output "UNION_EVENTS_MISSING_IN_ZIG=$($unionEventsVsZig.missingInZig.Count)"
if ($unionEventsVsZig.missingInZig.Count -gt 0) {
    Write-Output "UNION_EVENTS_MISSING_LIST_START"
    $unionEventsVsZig.missingInZig | Sort-Object | ForEach-Object { Write-Output $_ }
    Write-Output "UNION_EVENTS_MISSING_LIST_END"
}
Write-Output "UNION_EVENTS_EXTRA_IN_ZIG=$($unionEventsVsZig.extraInZig.Count)"

Write-Output "UNION_MISSING_IN_ZIG=$($unionVsZig.missingInZig.Count)"
if ($unionVsZig.missingInZig.Count -gt 0) {
    Write-Output "UNION_MISSING_METHODS_START"
    $unionVsZig.missingInZig | Sort-Object | ForEach-Object { Write-Output $_ }
    Write-Output "UNION_MISSING_METHODS_END"
}
Write-Output "UNION_EXTRA_IN_ZIG=$($unionVsZig.extraInZig.Count)"
if ($unionVsZig.extraInZig.Count -gt 0) {
    Write-Output "UNION_EXTRA_METHODS_START"
    $unionVsZig.extraInZig | Sort-Object | ForEach-Object { Write-Output $_ }
    Write-Output "UNION_EXTRA_METHODS_END"
}

if (-not [string]::IsNullOrWhiteSpace($OutputJsonPath)) {
    $outputDir = Split-Path -Parent $OutputJsonPath
    if (-not [string]::IsNullOrWhiteSpace($outputDir)) {
        New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
    }
    $reportJson = $report | ConvertTo-Json -Depth 10
    Set-Content -Path $OutputJsonPath -Value $reportJson -Encoding utf8
    Write-Output "PARITY_REPORT_JSON=$OutputJsonPath"
}

if (-not [string]::IsNullOrWhiteSpace($OutputMarkdownPath)) {
    $outputDir = Split-Path -Parent $OutputMarkdownPath
    if (-not [string]::IsNullOrWhiteSpace($outputDir)) {
        New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
    }

    $md = New-Object System.Collections.Generic.List[string]
    $tick = [string] [char] 96
    $md.Add("# Multi-Baseline Method/Event Parity Report") | Out-Null
    $md.Add("") | Out-Null
    $md.Add("Generated: $(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK')") | Out-Null
    $md.Add("") | Out-Null
    $md.Add("## Baselines") | Out-Null
    if (-not [string]::IsNullOrWhiteSpace($goRegistry.path)) {
        $md.Add("- Go baseline path: $tick$($goRegistry.path)$tick") | Out-Null
    }
    else {
        $md.Add("- Go baseline URL: $tick$($goRegistry.url)$tick") | Out-Null
    }
    if (-not [string]::IsNullOrWhiteSpace($goRegistry.ref)) {
        $md.Add("- Go baseline ref: $tick$($goRegistry.ref)$tick") | Out-Null
    }
    if (-not [string]::IsNullOrWhiteSpace($originalMethods.path)) {
        $md.Add("- Original baseline path: $tick$($originalMethods.path)$tick") | Out-Null
    }
    else {
        $md.Add("- Original baseline URL: $tick$($originalMethods.url)$tick") | Out-Null
    }
    if (-not [string]::IsNullOrWhiteSpace($originalMethods.ref)) {
        $md.Add("- Original baseline ref: $tick$($originalMethods.ref)$tick") | Out-Null
    }
    if (-not [string]::IsNullOrWhiteSpace($originalEvents.path)) {
        $md.Add("- Original events baseline path: $tick$($originalEvents.path)$tick") | Out-Null
    }
    else {
        $md.Add("- Original events baseline URL: $tick$($originalEvents.url)$tick") | Out-Null
    }
    if ($null -ne $originalBetaMethods) {
        if (-not [string]::IsNullOrWhiteSpace($originalBetaMethods.path)) {
            $md.Add("- Original beta baseline path: $tick$($originalBetaMethods.path)$tick") | Out-Null
        }
        else {
            $md.Add("- Original beta baseline URL: $tick$($originalBetaMethods.url)$tick") | Out-Null
        }
        if (-not [string]::IsNullOrWhiteSpace($originalBetaMethods.ref)) {
            $md.Add("- Original beta baseline ref: $tick$($originalBetaMethods.ref)$tick") | Out-Null
        }
        if (-not [string]::IsNullOrWhiteSpace($originalBetaEvents.path)) {
            $md.Add("- Original beta events baseline path: $tick$($originalBetaEvents.path)$tick") | Out-Null
        }
        else {
            $md.Add("- Original beta events baseline URL: $tick$($originalBetaEvents.url)$tick") | Out-Null
        }
    }
    $md.Add("- Zig registry path: $tick$ZigRegistryPath$tick") | Out-Null
    $md.Add("") | Out-Null
    $md.Add("## Counts") | Out-Null
    $md.Add("| Metric | Value |") | Out-Null
    $md.Add("| --- | ---: |") | Out-Null
    $md.Add("| Go methods | $($goMethods.Count) |") | Out-Null
    $md.Add("| Original methods | $($originalMethodSet.Count) |") | Out-Null
    $md.Add("| Original beta methods | $($originalBetaMethodSet.Count) |") | Out-Null
    $md.Add("| Union baseline methods | $($unionBaselineMethods.Count) |") | Out-Null
    $md.Add("| Zig methods | $($zigMethods.Count) |") | Out-Null
    $md.Add("| Original events | $($originalEventSet.Count) |") | Out-Null
    $md.Add("| Original beta events | $($originalBetaEventSet.Count) |") | Out-Null
    $md.Add("| Union baseline events | $($unionBaselineEvents.Count) |") | Out-Null
    $md.Add("| Zig events | $($zigEvents.Count) |") | Out-Null
    $md.Add("| Missing in Zig (Go baseline) | $($goVsZig.missingInZig.Count) |") | Out-Null
    $md.Add("| Missing in Zig (Original baseline) | $($originalVsZig.missingInZig.Count) |") | Out-Null
    $md.Add("| Missing in Zig (Original beta baseline) | $($originalBetaVsZig.missingInZig.Count) |") | Out-Null
    $md.Add("| Missing in Zig (Union baseline) | $($unionVsZig.missingInZig.Count) |") | Out-Null
    $md.Add("| Missing events in Zig (Original baseline) | $($originalEventsVsZig.missingInZig.Count) |") | Out-Null
    $md.Add("| Missing events in Zig (Original beta baseline) | $($originalBetaEventsVsZig.missingInZig.Count) |") | Out-Null
    $md.Add("| Missing events in Zig (Union baseline) | $($unionEventsVsZig.missingInZig.Count) |") | Out-Null
    $md.Add("| Extra in Zig (Go baseline) | $($goVsZig.extraInZig.Count) |") | Out-Null
    $md.Add("| Extra in Zig (Original baseline) | $($originalVsZig.extraInZig.Count) |") | Out-Null
    $md.Add("| Extra in Zig (Original beta baseline) | $($originalBetaVsZig.extraInZig.Count) |") | Out-Null
    $md.Add("| Extra in Zig (Union baseline) | $($unionVsZig.extraInZig.Count) |") | Out-Null
    $md.Add("| Extra events in Zig (Union baseline) | $($unionEventsVsZig.extraInZig.Count) |") | Out-Null
    $md.Add("") | Out-Null
    $md.Add("## Missing In Zig (Go Baseline)") | Out-Null
    if ($goVsZig.missingInZig.Count -eq 0) {
        $md.Add("- None") | Out-Null
    }
    else {
        foreach ($m in $goVsZig.missingInZig) {
            $md.Add("- $tick$m$tick") | Out-Null
        }
    }
    $md.Add("") | Out-Null
    $md.Add("## Missing In Zig (Original Baseline)") | Out-Null
    if ($originalVsZig.missingInZig.Count -eq 0) {
        $md.Add("- None") | Out-Null
    }
    else {
        foreach ($m in $originalVsZig.missingInZig) {
            $md.Add("- $tick$m$tick") | Out-Null
        }
    }
    $md.Add("") | Out-Null
    $md.Add("## Missing In Zig (Original Beta Baseline)") | Out-Null
    if ($originalBetaVsZig.missingInZig.Count -eq 0) {
        $md.Add("- None") | Out-Null
    }
    else {
        foreach ($m in $originalBetaVsZig.missingInZig) {
            $md.Add("- $tick$m$tick") | Out-Null
        }
    }
    $md.Add("") | Out-Null
    $md.Add("## Missing In Zig (Union Baseline)") | Out-Null
    if ($unionVsZig.missingInZig.Count -eq 0) {
        $md.Add("- None") | Out-Null
    }
    else {
        foreach ($m in $unionVsZig.missingInZig) {
            $md.Add("- $tick$m$tick") | Out-Null
        }
    }
    $md.Add("") | Out-Null
    $md.Add("## Missing Events In Zig (Original Baseline)") | Out-Null
    if ($originalEventsVsZig.missingInZig.Count -eq 0) {
        $md.Add("- None") | Out-Null
    }
    else {
        foreach ($m in $originalEventsVsZig.missingInZig) {
            $md.Add("- $tick$m$tick") | Out-Null
        }
    }
    $md.Add("") | Out-Null
    $md.Add("## Missing Events In Zig (Original Beta Baseline)") | Out-Null
    if ($originalBetaEventsVsZig.missingInZig.Count -eq 0) {
        $md.Add("- None") | Out-Null
    }
    else {
        foreach ($m in $originalBetaEventsVsZig.missingInZig) {
            $md.Add("- $tick$m$tick") | Out-Null
        }
    }
    $md.Add("") | Out-Null
    $md.Add("## Missing Events In Zig (Union Baseline)") | Out-Null
    if ($unionEventsVsZig.missingInZig.Count -eq 0) {
        $md.Add("- None") | Out-Null
    }
    else {
        foreach ($m in $unionEventsVsZig.missingInZig) {
            $md.Add("- $tick$m$tick") | Out-Null
        }
    }
    $md.Add("") | Out-Null
    $md.Add("## Extra In Zig (Union Baseline)") | Out-Null
    if ($unionVsZig.extraInZig.Count -eq 0) {
        $md.Add("- None") | Out-Null
    }
    else {
        foreach ($m in $unionVsZig.extraInZig) {
            $md.Add("- $tick$m$tick") | Out-Null
        }
    }
    $md.Add("") | Out-Null
    $md.Add("## Extra Events In Zig (Union Baseline)") | Out-Null
    if ($unionEventsVsZig.extraInZig.Count -eq 0) {
        $md.Add("- None") | Out-Null
    }
    else {
        foreach ($m in $unionEventsVsZig.extraInZig) {
            $md.Add("- $tick$m$tick") | Out-Null
        }
    }

    Set-Content -Path $OutputMarkdownPath -Value $md -Encoding utf8
    Write-Output "PARITY_REPORT_MD=$OutputMarkdownPath"
}

if ($goVsZig.missingInZig.Count -gt 0) {
    throw "Go->Zig parity check failed: missing methods in Zig = $($goVsZig.missingInZig.Count)"
}
if ($originalVsZig.missingInZig.Count -gt 0) {
    throw "Original->Zig parity check failed: missing methods in Zig = $($originalVsZig.missingInZig.Count)"
}
if ($originalBetaVsZig.missingInZig.Count -gt 0) {
    throw "Original beta->Zig parity check failed: missing methods in Zig = $($originalBetaVsZig.missingInZig.Count)"
}
if ($originalEventsVsZig.missingInZig.Count -gt 0) {
    throw "Original events->Zig parity check failed: missing events in Zig = $($originalEventsVsZig.missingInZig.Count)"
}
if ($originalBetaEventsVsZig.missingInZig.Count -gt 0) {
    throw "Original beta events->Zig parity check failed: missing events in Zig = $($originalBetaEventsVsZig.missingInZig.Count)"
}

if ($FailOnExtra -and $unionVsZig.extraInZig.Count -gt 0) {
    throw "Union baseline parity check failed: extra methods in Zig = $($unionVsZig.extraInZig.Count)"
}
if ($FailOnExtra -and $unionEventsVsZig.extraInZig.Count -gt 0) {
    throw "Union baseline parity check failed: extra events in Zig = $($unionEventsVsZig.extraInZig.Count)"
}

if ($null -eq $originalBetaMethods) {
    Write-Output "Go + Original -> Zig method/event parity check passed."
}
else {
    Write-Output "Go + Original + Original Beta -> Zig method/event parity check passed."
}
