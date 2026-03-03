$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$zigExe = "C:\users\ady\documents\toolchains\zig-master\current\zig.exe"

if (-not (Test-Path $zigExe)) {
    throw "Zig master executable not found at $zigExe"
}

Set-Location $repoRoot

$logRoot = Join-Path $repoRoot "release\arm64-diagnostics"
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null

$targets = @("aarch64-linux", "aarch64-macos")

function Invoke-BuildWithLogs {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Target
    )

    $stdout = Join-Path $logRoot ("build-" + $Target + ".stdout.log")
    $stderr = Join-Path $logRoot ("build-" + $Target + ".stderr.log")

    $proc = Start-Process -FilePath $zigExe -ArgumentList @("build", "-Dtarget=$Target", "-Doptimize=ReleaseFast", "--verbose") -RedirectStandardOutput $stdout -RedirectStandardError $stderr -NoNewWindow -Wait -PassThru
    $code = $proc.ExitCode
    return @{
        Target = $Target
        ExitCode = $code
        Stdout = $stdout
        Stderr = $stderr
    }
}

function Invoke-MinimalWithLogs {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Target
    )

    $tmpDir = Join-Path $repoRoot ".zig-cache\arm64-diagnostics"
    New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
    $source = Join-Path $tmpDir "minimal-main.zig"
    $emitPath = Join-Path $tmpDir ("minimal-" + $Target)

    Set-Content -Path $source -Value @'
const std = @import("std");
pub fn main() void {
    _ = std.mem.zeroes(u8);
}
'@ -Encoding utf8

    $stdout = Join-Path $logRoot ("minimal-" + $Target + ".stdout.log")
    $stderr = Join-Path $logRoot ("minimal-" + $Target + ".stderr.log")

    $proc = Start-Process -FilePath $zigExe -ArgumentList @("build-exe", $source, "-target", $Target, "-O", "ReleaseFast", "-femit-bin=$emitPath") -RedirectStandardOutput $stdout -RedirectStandardError $stderr -NoNewWindow -Wait -PassThru
    $code = $proc.ExitCode
    return @{
        Target = $Target
        ExitCode = $code
        Stdout = $stdout
        Stderr = $stderr
    }
}

Write-Output "Using Zig: $zigExe"
& $zigExe version

Write-Output ""
Write-Output "Running arm64 release cross-build diagnostics..."

foreach ($target in $targets) {
    $buildResult = Invoke-BuildWithLogs -Target $target
    Write-Output ("build target=" + $target + " exit=" + $buildResult.ExitCode)
    Write-Output ("  stdout: " + $buildResult.Stdout)
    Write-Output ("  stderr: " + $buildResult.Stderr)

    if ($buildResult.ExitCode -ne 0) {
        $minimalResult = Invoke-MinimalWithLogs -Target $target
        Write-Output ("minimal target=" + $target + " exit=" + $minimalResult.ExitCode)
        Write-Output ("  stdout: " + $minimalResult.Stdout)
        Write-Output ("  stderr: " + $minimalResult.Stderr)
    }
}

Write-Output ""
Write-Output ("Logs written under: " + $logRoot)
