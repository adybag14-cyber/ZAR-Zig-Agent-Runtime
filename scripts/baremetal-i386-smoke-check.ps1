# SPDX-License-Identifier: GPL-2.0-only
param(
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

function Read-UInt32LE {
    param([byte[]] $Bytes, [int] $Offset)
    return [System.BitConverter]::ToUInt32($Bytes, $Offset)
}

function Find-BytePatternIndex {
    param(
        [byte[]] $Bytes,
        [byte[]] $Pattern
    )
    if ($Pattern.Length -eq 0 -or $Bytes.Length -lt $Pattern.Length) {
        return -1
    }
    for ($i = 0; $i -le ($Bytes.Length - $Pattern.Length); $i++) {
        $matched = $true
        for ($j = 0; $j -lt $Pattern.Length; $j++) {
            if ($Bytes[$i + $j] -ne $Pattern[$j]) {
                $matched = $false
                break
            }
        }
        if ($matched) {
            return $i
        }
    }
    return -1
}

Set-Location $repo
$zig = Resolve-ZigExecutable

if (-not $SkipBuild) {
    & $zig build baremetal-i386 -Doptimize=ReleaseFast --summary all
    if ($LASTEXITCODE -ne 0) {
        throw "zig build baremetal-i386 failed with exit code $LASTEXITCODE"
    }
}

$artifactCandidates = @(
    (Join-Path $repo "zig-out\bin\openclaw-zig-baremetal-i386.elf"),
    (Join-Path $repo "zig-out/openclaw-zig-baremetal-i386.elf"),
    (Join-Path $repo "zig-out\openclaw-zig-baremetal-i386.elf")
)

$artifact = $null
foreach ($candidate in $artifactCandidates) {
    if (Test-Path $candidate) {
        $artifact = (Resolve-Path $candidate).Path
        break
    }
}
if ($null -eq $artifact) {
    throw "i386 bare-metal artifact not found after build."
}

$bytes = [System.IO.File]::ReadAllBytes($artifact)
if ($bytes.Length -lt 64) {
    throw "artifact too small for ELF header: $artifact"
}
if ($bytes[0] -ne 0x7F -or $bytes[1] -ne 0x45 -or $bytes[2] -ne 0x4C -or $bytes[3] -ne 0x46) {
    throw "artifact is not an ELF binary: $artifact"
}
if ($bytes[4] -ne 1) {
    throw "artifact is not ELF32 (EI_CLASS != 1)"
}
if ($bytes[5] -ne 1) {
    throw "artifact is not little-endian ELF (EI_DATA != 1)"
}

$multiboot2Magic = [byte[]] @(0xD6, 0x50, 0x52, 0xE8)
$multibootOffset = Find-BytePatternIndex -Bytes $bytes -Pattern $multiboot2Magic
if ($multibootOffset -lt 0) {
    throw "multiboot2 header magic not found in i386 artifact"
}
if ($multibootOffset -ge 32768) {
    throw "multiboot2 header was not found in first 32768 bytes (offset=$multibootOffset)"
}
if (($multibootOffset % 8) -ne 0) {
    throw "multiboot2 header is not 8-byte aligned (offset=$multibootOffset)"
}

$architecture = Read-UInt32LE -Bytes $bytes -Offset ($multibootOffset + 4)
if ($architecture -ne 0) {
    throw "unsupported multiboot2 architecture value: $architecture (expected 0)"
}

Write-Output "BAREMETAL_I386_ARTIFACT=$artifact"
Write-Output "BAREMETAL_I386_ELF32=True"
Write-Output "BAREMETAL_I386_MULTIBOOT2=True"
Write-Output "BAREMETAL_I386_SMOKE=pass"
