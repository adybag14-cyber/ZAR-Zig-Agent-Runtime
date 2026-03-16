# SPDX-License-Identifier: GPL-2.0-only
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$zigExe = "C:\users\ady\documents\toolchains\zig-master\current\zig.exe"

if (-not (Test-Path $zigExe)) {
    throw "Zig master executable not found at $zigExe"
}

$zigDir = Split-Path -Parent $zigExe
$env:PATH = "$zigDir;$env:PATH"

Write-Output "Zig master enabled from $zigDir"
& $zigExe version
