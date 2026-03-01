$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$zigExe = "C:\users\ady\documents\toolchains\zig-master\current\zig.exe"

if (-not (Test-Path $zigExe)) {
    throw "Zig master executable not found at $zigExe"
}

Set-Location $repoRoot

function Invoke-ZigChecked {
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $Args
    )
    & $zigExe @Args
    if ($LASTEXITCODE -ne 0) {
        throw "zig $($Args -join ' ') failed with exit code $LASTEXITCODE"
    }
}

Write-Output "Using Zig: $zigExe"
Invoke-ZigChecked -Args @("version")

Write-Output "`n[1/4] zig fmt --check"
Invoke-ZigChecked -Args @("fmt", "--check", ".\src\main.zig", ".\build.zig")

Write-Output "`n[2/4] zig build"
Invoke-ZigChecked -Args @("build")

Write-Output "`n[3/4] zig build test"
Invoke-ZigChecked -Args @("build", "test")

Write-Output "`n[4/4] zig build run"
Invoke-ZigChecked -Args @("build", "run")

Write-Output "`nZig syntax/build checks passed."
