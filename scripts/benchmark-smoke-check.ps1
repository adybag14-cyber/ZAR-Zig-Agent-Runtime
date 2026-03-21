# SPDX-License-Identifier: GPL-2.0-only
param(
    [int] $DurationMs = 25,
    [int] $WarmupMs = 5,
    [string] $Filter = "protocol.dns_roundtrip",
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"

$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

function Resolve-ZigExecutable {
    $defaultWindowsZig = "C:\Users\Ady\Documents\toolchains\zig-master\current\zig.exe"
    if ($env:OPENCLAW_ZIG_BIN -and $env:OPENCLAW_ZIG_BIN.Trim().Length -gt 0) {
        if (-not (Test-Path $env:OPENCLAW_ZIG_BIN)) {
            throw "OPENCLAW_ZIG_BIN is set but not found: $($env:OPENCLAW_ZIG_BIN)"
        }
        return $env:OPENCLAW_ZIG_BIN
    }

    $zigCmd = Get-Command zig -ErrorAction SilentlyContinue
    if ($null -ne $zigCmd -and $zigCmd.Path) {
        return $zigCmd.Path
    }

    if (Test-Path $defaultWindowsZig) {
        return $defaultWindowsZig
    }

    throw "Zig executable not found. Set OPENCLAW_ZIG_BIN or ensure `zig` is on PATH."
}

$zig = Resolve-ZigExecutable
if (-not $SkipBuild) {
    & $zig build --summary all
    if ($LASTEXITCODE -ne 0) {
        throw "zig build failed with exit code $LASTEXITCODE"
    }
}

$outputPath = Join-Path $repo "tmp_benchmark_smoke_output.txt"
Remove-Item $outputPath -ErrorAction SilentlyContinue

Push-Location $repo
try {
    & $zig build bench -- --duration-ms "$DurationMs" --warmup-ms "$WarmupMs" --filter "$Filter" 2>&1 | Tee-Object -FilePath $outputPath | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "zig build bench failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}

$output = Get-Content -Path $outputPath -Raw
if ($output -notmatch 'BENCH:START') {
    throw "Benchmark smoke output is missing BENCH:START"
}
if ($output -notmatch ("BENCH:CASE name=" + [regex]::Escape($Filter))) {
    throw "Benchmark smoke output is missing the requested BENCH:CASE for $Filter"
}
if ($output -notmatch 'BENCH:END cases=1') {
    throw "Benchmark smoke output is missing BENCH:END cases=1"
}

Write-Output "BENCH_SMOKE_FILTER=$Filter"
Write-Output "BENCH_SMOKE_DURATION_MS=$DurationMs"
Write-Output "BENCH_SMOKE_WARMUP_MS=$WarmupMs"
