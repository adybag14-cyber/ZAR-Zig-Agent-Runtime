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

Set-Location $repo
$zig = Resolve-ZigExecutable

& $zig build baremetal --summary all
if ($LASTEXITCODE -ne 0) {
    throw "zig build baremetal failed with exit code $LASTEXITCODE"
}

$candidates = @(
    (Join-Path $repo "zig-out\openclaw-zig-baremetal.elf"),
    (Join-Path $repo "zig-out/openclaw-zig-baremetal.elf"),
    (Join-Path $repo "zig-out\bin\openclaw-zig-baremetal.elf"),
    (Join-Path $repo "zig-out/bin/openclaw-zig-baremetal.elf")
)

$artifact = $null
foreach ($candidate in $candidates) {
    if (Test-Path $candidate) {
        $artifact = (Resolve-Path $candidate).Path
        break
    }
}

if ($null -eq $artifact) {
    throw "bare-metal artifact not found in expected zig-out paths."
}

$info = Get-Item $artifact
if ($info.Length -le 0) {
    throw "bare-metal artifact is empty: $artifact"
}

Write-Output "BAREMETAL_BUILD_HTTP=200"
Write-Output "BAREMETAL_ARTIFACT=$artifact"
Write-Output "BAREMETAL_SIZE_BYTES=$($info.Length)"
