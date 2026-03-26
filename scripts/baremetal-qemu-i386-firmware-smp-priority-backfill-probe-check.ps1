# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 60,
    [int] $MemoryMiB = 128
)

$ErrorActionPreference = "Stop"

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

function Resolve-QemuExecutable {
    $candidates = @(
        "qemu-system-i386",
        "qemu-system-i386.exe",
        "C:\Program Files\qemu\qemu-system-i386.exe"
    )

    foreach ($name in $candidates) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($null -ne $cmd -and $cmd.Path) {
            return $cmd.Path
        }
        if (Test-Path $name) {
            return (Resolve-Path $name).Path
        }
    }

    return $null
}

function Remove-PathIfPresent {
    param([string] $Path)
    if (-not (Test-Path $Path)) { return }
    try {
        Remove-Item -Force -ErrorAction Stop $Path
    } catch [System.Management.Automation.ItemNotFoundException] {
        return
    }
}

Set-Location (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$repo = (Get-Location).Path
$releaseDir = Join-Path $repo "release"
$scriptStem = [System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
$variantStem = "{0}-{1}m" -f $scriptStem, $MemoryMiB
$buildPrefix = Join-Path $repo ("zig-out\" + $variantStem)
$env:ZIG_LOCAL_CACHE_DIR = Join-Path $repo (".zig-cache-" + $variantStem)
$env:ZIG_GLOBAL_CACHE_DIR = Join-Path $repo (".zig-global-cache-" + $variantStem)
New-Item -ItemType Directory -Force -Path $buildPrefix | Out-Null
New-Item -ItemType Directory -Force -Path $releaseDir | Out-Null

$zig = Resolve-ZigExecutable
$qemu = Resolve-QemuExecutable
if ($null -eq $qemu) {
    Write-Output "BAREMETAL_I386_QEMU_AVAILABLE=False"
    Write-Output "BAREMETAL_I386_FIRMWARE_SMP_PRIORITY_BACKFILL_PROBE=skipped"
    return
}

$probeCode = 0x84
$expectedExitCodes = @{
    (($probeCode * 2) + 1) = $probeCode
}

if (-not $SkipBuild) {
    & $zig build baremetal-i386 -Doptimize=ReleaseFast -Dbaremetal-i386-smp-priority-backfill-probe=true --prefix $buildPrefix --summary all
    if ($LASTEXITCODE -ne 0) {
        throw "zig build baremetal-i386 -Dbaremetal-i386-smp-priority-backfill-probe=true failed with exit code $LASTEXITCODE"
    }
}

$artifactCandidates = @(
    (Join-Path $buildPrefix "bin\openclaw-zig-baremetal-i386.elf"),
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
    throw "i386 bare-metal firmware SMP priority backfill artifact not found after build."
}

$firmwareImage = Join-Path $releaseDir ("qemu-i386-firmware-smp-priority-backfill-probe-{0}m.img" -f $MemoryMiB)
$firmwareMetadata = Join-Path $releaseDir ("qemu-i386-firmware-smp-priority-backfill-probe-{0}m.meta.txt" -f $MemoryMiB)
$stdoutPath = Join-Path $releaseDir ("qemu-i386-firmware-smp-priority-backfill-probe-{0}m-stdout.log" -f $MemoryMiB)
$stderrPath = Join-Path $releaseDir ("qemu-i386-firmware-smp-priority-backfill-probe-{0}m-stderr.log" -f $MemoryMiB)
$debugLogPath = Join-Path $releaseDir ("qemu-i386-firmware-smp-priority-backfill-probe-{0}m-debug.log" -f $MemoryMiB)

Remove-PathIfPresent $stdoutPath
Remove-PathIfPresent $stderrPath
Remove-PathIfPresent $debugLogPath
Remove-PathIfPresent $firmwareImage
Remove-PathIfPresent $firmwareMetadata

powershell -ExecutionPolicy Bypass -File (Join-Path $repo 'scripts\build-i386-firmware-image.ps1') `
    -ArtifactPath $artifact `
    -OutputImagePath $firmwareImage `
    -OutputMetadataPath $firmwareMetadata
if ($LASTEXITCODE -ne 0) {
    throw "i386 firmware image build failed with exit code $LASTEXITCODE"
}

$qemuArgs = @(
    "-M", "q35,accel=tcg",
    "-m", ("{0}M" -f $MemoryMiB),
    "-smp", "5",
    "-drive", ("format=raw,file={0},if=ide,index=0" -f $firmwareImage),
    "-boot", "c",
    "-display", "none",
    "-serial", "none",
    "-monitor", "none",
    "-no-reboot",
    "-no-shutdown",
    "-debugcon", ("file:{0}" -f $debugLogPath),
    "-global", "isa-debugcon.iobase=0xe9",
    "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04"
)

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $qemu
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.Arguments = (($qemuArgs | ForEach-Object {
    if ("$_" -match '[\s"]') {
        '"{0}"' -f (($_ -replace '"', '\"'))
    } else {
        "$_"
    }
}) -join ' ')

$proc = New-Object System.Diagnostics.Process
$proc.StartInfo = $psi
[void]$proc.Start()
$stdoutTask = $proc.StandardOutput.ReadToEndAsync()
$stderrTask = $proc.StandardError.ReadToEndAsync()

if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
    try { $proc.Kill($true) } catch {}
    $debugTail = ""
    if (Test-Path $debugLogPath) {
        $debugTail = (Get-Content -Path $debugLogPath -Tail 80 -ErrorAction SilentlyContinue) -join "`n"
    }
    if ([string]::IsNullOrWhiteSpace($debugTail)) {
    throw "QEMU i386 firmware SMP priority backfill probe timed out after $TimeoutSeconds seconds."
    }
    throw "QEMU i386 firmware SMP priority backfill probe timed out after $TimeoutSeconds seconds.`n$debugTail"
}

$proc.WaitForExit()
$stdout = $stdoutTask.GetAwaiter().GetResult()
$stderr = $stderrTask.GetAwaiter().GetResult()
Set-Content -Path $stdoutPath -Value $stdout -Encoding Ascii
Set-Content -Path $stderrPath -Value $stderr -Encoding Ascii
$exitCode = $proc.ExitCode
if (-not $expectedExitCodes.ContainsKey($exitCode)) {
    $stderrTail = ""
    if (Test-Path $stderrPath) {
        $stderrTail = (Get-Content -Path $stderrPath -Tail 40 -ErrorAction SilentlyContinue) -join "`n"
    }
    $debugTail = ""
    if (Test-Path $debugLogPath) {
        $debugTail = (Get-Content -Path $debugLogPath -Tail 80 -ErrorAction SilentlyContinue) -join "`n"
    }
    $expectedText = ($expectedExitCodes.Keys | Sort-Object) -join ", "
    throw "QEMU i386 firmware SMP priority backfill probe failed: exit=$exitCode expected one of [$expectedText]`n$stderrTail`n$debugTail"
}

$observedProbeCode = [int]$expectedExitCodes[$exitCode]

Write-Output "BAREMETAL_I386_QEMU_AVAILABLE=True"
Write-Output "BAREMETAL_I386_QEMU_BINARY=$qemu"
Write-Output "BAREMETAL_I386_QEMU_ARTIFACT=$artifact"
Write-Output "BAREMETAL_I386_QEMU_FIRMWARE_IMAGE=$firmwareImage"
Write-Output "BAREMETAL_I386_QEMU_FIRMWARE_METADATA=$firmwareMetadata"
Write-Output "BAREMETAL_I386_QEMU_MEMORY_MIB=$MemoryMiB"
Write-Output ("BAREMETAL_I386_QEMU_EXPECTED_EXIT_CODES={0}" -f (($expectedExitCodes.Keys | Sort-Object) -join ","))
Write-Output "BAREMETAL_I386_QEMU_EXIT_CODE=$exitCode"
Write-Output ("BAREMETAL_I386_QEMU_FIRMWARE_SMP_PRIORITY_BACKFILL_PROBE_CODE=0x{0:X2}" -f $observedProbeCode)
Write-Output "BAREMETAL_I386_QEMU_FIRMWARE_SMP_PRIORITY_BACKFILL_PROBE_DEBUG=$debugLogPath"
Write-Output "BAREMETAL_I386_FIRMWARE_SMP_PRIORITY_BACKFILL_PROBE=pass"




