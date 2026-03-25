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

function Read-CString {
    param(
        [byte[]] $Table,
        [int] $Offset
    )
    if ($Offset -lt 0 -or $Offset -ge $Table.Length) {
        return ""
    }
    $builder = [System.Text.StringBuilder]::new()
    for ($idx = $Offset; $idx -lt $Table.Length; $idx++) {
        $value = $Table[$idx]
        if ($value -eq 0) {
            break
        }
        [void]$builder.Append([char]$value)
    }
    return $builder.ToString()
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

$elfHeaderOffset = [int][System.BitConverter]::ToUInt32($bytes, 32)
$sectionHeaderEntrySize = [int][System.BitConverter]::ToUInt16($bytes, 46)
$sectionHeaderCount = [int][System.BitConverter]::ToUInt16($bytes, 48)
$sectionNameIndex = [int][System.BitConverter]::ToUInt16($bytes, 50)
if ($sectionHeaderEntrySize -le 0 -or $sectionHeaderCount -le 0) {
    throw "ELF section header table missing from i386 artifact"
}

$sections = @()
for ($i = 0; $i -lt $sectionHeaderCount; $i++) {
    $entryBase = $elfHeaderOffset + ($i * $sectionHeaderEntrySize)
    $nameIndex = [int][System.BitConverter]::ToUInt32($bytes, $entryBase)
    $type = [int][System.BitConverter]::ToUInt32($bytes, $entryBase + 4)
    $offset = [int][System.BitConverter]::ToUInt32($bytes, $entryBase + 16)
    $size = [int][System.BitConverter]::ToUInt32($bytes, $entryBase + 20)
    $link = [int][System.BitConverter]::ToUInt32($bytes, $entryBase + 24)
    $entrySize = [int][System.BitConverter]::ToUInt32($bytes, $entryBase + 36)
    $sections += [pscustomobject]@{
        NameIndex = $nameIndex
        Type = $type
        Offset = $offset
        Size = $size
        Link = $link
        EntrySize = $entrySize
    }
}

if ($sectionNameIndex -lt 0 -or $sectionNameIndex -ge $sections.Count) {
    throw "ELF section-name string table index is invalid"
}

$shstr = $sections[$sectionNameIndex]
$shstrBytes = New-Object byte[] $shstr.Size
[Array]::Copy($bytes, $shstr.Offset, $shstrBytes, 0, $shstr.Size)
foreach ($section in $sections) {
    $section | Add-Member -NotePropertyName Name -NotePropertyValue (Read-CString -Table $shstrBytes -Offset $section.NameIndex)
}

$symtab = $sections | Where-Object { $_.Type -eq 2 } | Select-Object -First 1
if ($null -eq $symtab -or $symtab.EntrySize -le 0) {
    throw "ELF symbol table missing from i386 artifact"
}

$strtab = $sections[$symtab.Link]
$symbolStringTable = New-Object byte[] $strtab.Size
[Array]::Copy($bytes, $strtab.Offset, $symbolStringTable, 0, $strtab.Size)

$symbolCount = [int]($symtab.Size / $symtab.EntrySize)
$symbols = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
for ($i = 0; $i -lt $symbolCount; $i++) {
    $entryBase = $symtab.Offset + ($i * $symtab.EntrySize)
    $nameOffset = [int](Read-UInt32LE -Bytes $bytes -Offset $entryBase)
    if ($nameOffset -le 0) {
        continue
    }
    $name = Read-CString -Table $symbolStringTable -Offset $nameOffset
    if (-not [string]::IsNullOrWhiteSpace($name)) {
        [void]$symbols.Add($name)
    }
}

$requiredSymbols = @(
    "_start",
    "oc_gdtr_ptr",
    "oc_idtr_ptr",
    "oc_gdt_ptr",
    "oc_idt_ptr",
    "oc_descriptor_tables_ready",
    "oc_descriptor_tables_loaded",
    "oc_descriptor_load_attempt_count",
    "oc_descriptor_load_success_count",
    "oc_try_load_descriptor_tables",
    "oc_acpi_state_ptr",
    "oc_cpu_topology_state_ptr",
    "oc_cpu_topology_entry_count",
    "oc_cpu_topology_entry",
    "oc_lapic_state_ptr",
    "oc_i386_ap_startup_state_ptr"
)
foreach ($required in $requiredSymbols) {
    if (-not $symbols.Contains($required)) {
        throw "required symbol not found in i386 ELF symtab: $required"
    }
}

Write-Output "BAREMETAL_I386_ARTIFACT=$artifact"
Write-Output "BAREMETAL_I386_ELF32=True"
Write-Output "BAREMETAL_I386_MULTIBOOT2=True"
Write-Output "BAREMETAL_I386_DESCRIPTOR_EXPORTS=True"
Write-Output "BAREMETAL_I386_SMOKE=pass"
