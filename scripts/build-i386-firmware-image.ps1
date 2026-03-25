# SPDX-License-Identifier: GPL-2.0-only
param(
    [Parameter(Mandatory = $true)]
    [string] $ArtifactPath,
    [Parameter(Mandatory = $true)]
    [string] $OutputImagePath,
    [string] $OutputMetadataPath
)

$ErrorActionPreference = "Stop"

function Resolve-RequiredTool {
    param([string[]] $Candidates, [string] $Name)
    foreach ($candidate in $Candidates) {
        $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($cmd -and $cmd.Path) { return $cmd.Path }
        if (Test-Path $candidate) { return (Resolve-Path $candidate).Path }
    }
    throw "Required tool not found: $Name"
}

function Write-PaddedBytes {
    param(
        [System.IO.BinaryWriter] $Writer,
        [byte[]] $Bytes,
        [int] $Alignment
    )
    $Writer.Write($Bytes)
    $padding = ($Alignment - ($Bytes.Length % $Alignment)) % $Alignment
    for ($i = 0; $i -lt $padding; $i += 1) {
        $Writer.Write([byte]0)
    }
    return ($Bytes.Length + $padding)
}

$artifact = (Resolve-Path $ArtifactPath).Path
$outputImage = [System.IO.Path]::GetFullPath($OutputImagePath)
$outputDir = Split-Path $outputImage -Parent
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$nasm = Resolve-RequiredTool @(
    "nasm",
    "nasm.exe",
    "C:\Users\Ady\AppData\Local\Microsoft\WinGet\Packages\BrechtSanders.WinLibs.POSIX.UCRT_Microsoft.Winget.Source_8wekyb3d8bbwe\mingw64\bin\nasm.exe"
) "nasm"
$readelf = Resolve-RequiredTool @(
    "readelf",
    "readelf.exe",
    "C:\Users\Ady\AppData\Local\Microsoft\WinGet\Packages\BrechtSanders.WinLibs.POSIX.UCRT_Microsoft.Winget.Source_8wekyb3d8bbwe\mingw64\bin\readelf.exe"
) "readelf"
$nm = Resolve-RequiredTool @(
    "nm",
    "nm.exe",
    "C:\Users\Ady\AppData\Local\Microsoft\WinGet\Packages\BrechtSanders.WinLibs.POSIX.UCRT_Microsoft.Winget.Source_8wekyb3d8bbwe\mingw64\bin\nm.exe"
) "nm"

$stage2Sectors = 16
$headerLba = 1 + $stage2Sectors
$payloadLba = $headerLba + 1
$headerMagic = 0x3146525A
$headerVersion = 1

$scratchDir = Join-Path $outputDir ([System.IO.Path]::GetFileNameWithoutExtension($outputImage) + "-firmware-build")
New-Item -ItemType Directory -Force -Path $scratchDir | Out-Null
$stage1Bin = Join-Path $scratchDir "stage1.bin"
$stage2Bin = Join-Path $scratchDir "stage2.bin"

$readelfOutput = & $readelf -lW $artifact
if ($LASTEXITCODE -ne 0) { throw "readelf failed for $artifact" }
$entryMatch = [regex]::Match(($readelfOutput -join "`n"), 'Entry point 0x(?<entry>[0-9A-Fa-f]+)')
if (-not $entryMatch.Success) { throw "Failed to resolve ELF entry point from $artifact" }
$elfEntryAddress = [Convert]::ToUInt32($entryMatch.Groups["entry"].Value, 16)

$segments = New-Object System.Collections.Generic.List[object]
foreach ($line in $readelfOutput) {
    if ($line -notmatch '^\s*LOAD\s+') { continue }
    $parts = ($line.Trim() -split '\s+')
    if ($parts.Count -lt 7) { continue }
    $flags = if ($parts.Count -gt 7) { ($parts[6..($parts.Count - 2)] -join "") } else { $parts[6] }

    $segment = [pscustomobject]@{
        Offset      = [Convert]::ToInt32($parts[1].Substring(2), 16)
        PhysAddr    = [Convert]::ToUInt32($parts[3].Substring(2), 16)
        FileSize    = [Convert]::ToUInt32($parts[4].Substring(2), 16)
        MemSize     = [Convert]::ToUInt32($parts[5].Substring(2), 16)
        Flags       = $flags
        PayloadLba = [uint32]0
        SectorCount = [uint32]0
    }
    $segments.Add($segment)
}
if ($segments.Count -eq 0) { throw "No PT_LOAD segments found in $artifact" }

$artifactBytes = [System.IO.File]::ReadAllBytes($artifact)
$payloadBlobs = New-Object System.Collections.Generic.List[byte[]]
$currentLba = [uint32]$payloadLba
for ($index = 0; $index -lt $segments.Count; $index += 1) {
    $segment = $segments[$index]
    if ($segment.FileSize -gt 0) {
        $blob = New-Object byte[] $segment.FileSize
        [Array]::Copy($artifactBytes, $segment.Offset, $blob, 0, $segment.FileSize)
        $sectorCount = [uint32][Math]::Ceiling($segment.FileSize / 512.0)
        $segment.PayloadLba = $currentLba
        $segment.SectorCount = $sectorCount
        $currentLba += $sectorCount
        $payloadBlobs.Add($blob)
    } else {
        $payloadBlobs.Add((New-Object byte[] 0))
    }
    $segments[$index] = $segment
}

$bootSymbol = (& $nm $artifact | Where-Object { $_ -match '\s[tT]\smultiboot32_start$' } | Select-Object -First 1)
if (-not $bootSymbol) { throw "Failed to resolve multiboot32_start from $artifact" }
$bootAddress = [Convert]::ToUInt32((($bootSymbol.Trim() -split '\s+')[0]), 16)

& $nasm "-f" "bin" (Join-Path $repo "scripts\baremetal\i386_bios_boot_sector.asm") "-o" $stage1Bin "-D" "STAGE2_SECTORS=$stage2Sectors"
if ($LASTEXITCODE -ne 0) { throw "nasm failed while assembling the BIOS boot sector" }

& $nasm "-f" "bin" (Join-Path $repo "scripts\baremetal\i386_bios_stage2.asm") "-o" $stage2Bin "-D" "HEADER_LBA=$headerLba"
if ($LASTEXITCODE -ne 0) { throw "nasm failed while assembling the BIOS stage-2 loader" }

$stage1Bytes = [System.IO.File]::ReadAllBytes($stage1Bin)
$stage2Bytes = [System.IO.File]::ReadAllBytes($stage2Bin)
if ($stage1Bytes.Length -ne 512) { throw "BIOS boot sector is not 512 bytes: $($stage1Bytes.Length)" }
if ($stage2Bytes.Length -gt ($stage2Sectors * 512)) {
    throw "BIOS stage-2 loader exceeds reserved space ($($stage2Bytes.Length) > $($stage2Sectors * 512))"
}

$headerStream = New-Object System.IO.MemoryStream
$headerWriter = New-Object System.IO.BinaryWriter($headerStream)
$headerWriter.Write([uint32]$headerMagic)
$headerWriter.Write([uint16]$headerVersion)
$headerWriter.Write([uint16]$segments.Count)
$headerWriter.Write([uint32]$bootAddress)
$headerWriter.Write([uint32]0)
foreach ($segment in $segments) {
    $headerWriter.Write([uint32]$segment.PhysAddr)
    $headerWriter.Write([uint32]$segment.PayloadLba)
    $headerWriter.Write([uint32]$segment.SectorCount)
    $headerWriter.Write([uint32]$segment.FileSize)
    $headerWriter.Write([uint32]$segment.MemSize)
}
$headerWriter.Flush()
$headerBytes = $headerStream.ToArray()
if ($headerBytes.Length -gt 512) { throw "Firmware loader header exceeds one sector: $($headerBytes.Length) bytes" }

$imageStream = [System.IO.File]::Open($outputImage, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
try {
    $writer = New-Object System.IO.BinaryWriter($imageStream)
    $writer.Write($stage1Bytes)
    $stage2Padding = ($stage2Sectors * 512) - $stage2Bytes.Length
    $writer.Write($stage2Bytes)
    for ($i = 0; $i -lt $stage2Padding; $i += 1) {
        $writer.Write([byte]0)
    }
    [void](Write-PaddedBytes -Writer $writer -Bytes $headerBytes -Alignment 512)
    foreach ($blob in $payloadBlobs) {
        if ($blob.Length -eq 0) { continue }
        [void](Write-PaddedBytes -Writer $writer -Bytes $blob -Alignment 512)
    }
    $writer.Flush()
} finally {
    $imageStream.Dispose()
}

Write-Output "BAREMETAL_I386_FIRMWARE_IMAGE=$outputImage"
Write-Output ("BAREMETAL_I386_FIRMWARE_ENTRY=0x{0:X8}" -f $bootAddress)
Write-Output ("BAREMETAL_I386_FIRMWARE_BOOT_SYMBOL=0x{0:X8}" -f $bootAddress)
Write-Output ("BAREMETAL_I386_FIRMWARE_ELF_ENTRY=0x{0:X8}" -f $elfEntryAddress)
Write-Output "BAREMETAL_I386_FIRMWARE_STAGE2_SECTORS=$stage2Sectors"
Write-Output "BAREMETAL_I386_FIRMWARE_SEGMENT_COUNT=$($segments.Count)"
Write-Output "BAREMETAL_I386_FIRMWARE_TOTAL_SECTORS=$currentLba"

if ($OutputMetadataPath) {
    $metadataLines = New-Object System.Collections.Generic.List[string]
    $metadataLines.Add("entry=0x{0:X8}" -f $bootAddress) | Out-Null
    $metadataLines.Add("boot_symbol=0x{0:X8}" -f $bootAddress) | Out-Null
    $metadataLines.Add("elf_entry=0x{0:X8}" -f $elfEntryAddress) | Out-Null
    $metadataLines.Add("stage2_sectors=$stage2Sectors") | Out-Null
    $metadataLines.Add("segment_count=$($segments.Count)") | Out-Null
    $segmentIndex = 0
    foreach ($segment in $segments) {
        $metadataLines.Add([string]::Format(
                "segment[{0}]=phys=0x{1:X8},lba={2},sectors={3},filesz=0x{4:X},memsz=0x{5:X},flags={6}",
                $segmentIndex, $segment.PhysAddr, $segment.PayloadLba, $segment.SectorCount, $segment.FileSize, $segment.MemSize, $segment.Flags
            )) | Out-Null
        $segmentIndex += 1
    }
    $metadataDir = Split-Path $OutputMetadataPath -Parent
    if ($metadataDir) { New-Item -ItemType Directory -Force -Path $metadataDir | Out-Null }
    Set-Content -Path $OutputMetadataPath -Value $metadataLines -Encoding Ascii
}
