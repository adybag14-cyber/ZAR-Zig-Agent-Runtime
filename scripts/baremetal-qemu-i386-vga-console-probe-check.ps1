# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 30,
    [int] $GdbPort = 0
)

$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$releaseDir = Join-Path $repo 'release'
$runStamp = [DateTime]::UtcNow.ToString('yyyyMMddHHmmssfff')

$consoleMagic = 0x4f43434e
$apiVersion = 2
$consoleBackendVgaText = 1
$expectedCols = 80
$expectedRows = 25
$vgaBufferAddr = '0xB8000'
$consoleMagicOffset = 0
$consoleApiVersionOffset = 4
$consoleColsOffset = 6
$consoleRowsOffset = 8
$consoleCursorRowOffset = 10
$consoleCursorColOffset = 12
$consoleBackendOffset = 15
$consoleWriteCountOffset = 20
$consoleClearCountOffset = 28

function Resolve-ZigExecutable {
    $default = 'C:\Users\Ady\Documents\toolchains\zig-master\current\zig.exe'
    if ($env:OPENCLAW_ZIG_BIN -and $env:OPENCLAW_ZIG_BIN.Trim().Length -gt 0) {
        if (-not (Test-Path $env:OPENCLAW_ZIG_BIN)) { throw "OPENCLAW_ZIG_BIN is set but not found: $($env:OPENCLAW_ZIG_BIN)" }
        return $env:OPENCLAW_ZIG_BIN
    }
    $cmd = Get-Command zig -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Path) { return $cmd.Path }
    if (Test-Path $default) { return $default }
    throw 'Zig executable not found.'
}

function Resolve-PreferredExecutable {
    param([string[]] $Candidates)
    foreach ($name in $Candidates) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd -and $cmd.Path) { return $cmd.Path }
        if (Test-Path $name) { return (Resolve-Path $name).Path }
    }
    return $null
}

function Resolve-QemuExecutable { return Resolve-PreferredExecutable @('qemu-system-i386', 'qemu-system-i386.exe', 'C:\Program Files\qemu\qemu-system-i386.exe') }
function Resolve-GdbExecutable { return Resolve-PreferredExecutable @('gdb', 'gdb.exe') }
function Resolve-NmExecutable { return Resolve-PreferredExecutable @('llvm-nm', 'llvm-nm.exe', 'nm', 'nm.exe', 'C:\Users\Ady\Documents\starpro\tooling\emsdk\upstream\bin\llvm-nm.exe') }

function Resolve-FreeTcpPort {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    try {
        $listener.Start()
        return ([System.Net.IPEndPoint] $listener.LocalEndpoint).Port
    } finally {
        $listener.Stop()
    }
}

function Resolve-SymbolAddress {
    param([string[]] $SymbolLines, [string] $Pattern, [string] $SymbolName)
    $line = $SymbolLines | Where-Object { $_ -match $Pattern } | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($line)) { throw "Failed to resolve symbol address for $SymbolName" }
    $parts = ($line.Trim() -split '\s+')
    if ($parts.Count -lt 3) { throw "Unexpected symbol line while resolving ${SymbolName}: $line" }
    return $parts[0]
}

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $pattern = '(?m)^' + [regex]::Escape($Name) + '=(-?\d+)$'
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

function Remove-PathWithRetry {
    param([string] $Path)
    if (-not (Test-Path $Path)) { return }
    for ($attempt = 0; $attempt -lt 5; $attempt += 1) {
        try {
            Remove-Item -Force -ErrorAction Stop $Path
            return
        } catch {
            if ($attempt -ge 4) { throw }
            Start-Sleep -Milliseconds 100
        }
    }
}

Set-Location $repo
New-Item -ItemType Directory -Force -Path $releaseDir | Out-Null
$scriptStem = [System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
$buildPrefix = Join-Path $repo ("zig-out\" + $scriptStem)
$env:ZIG_LOCAL_CACHE_DIR = Join-Path $repo (".zig-cache-" + $scriptStem)
$env:ZIG_GLOBAL_CACHE_DIR = Join-Path $repo (".zig-global-cache-" + $scriptStem)
New-Item -ItemType Directory -Force -Path $buildPrefix | Out-Null

$zig = Resolve-ZigExecutable
$qemu = Resolve-QemuExecutable
$gdb = Resolve-GdbExecutable
$nm = Resolve-NmExecutable

if ($null -eq $qemu -or $null -eq $gdb -or $null -eq $nm) {
    Write-Output "BAREMETAL_I386_QEMU_AVAILABLE=$([bool]($null -ne $qemu))"
    Write-Output "BAREMETAL_I386_GDB_AVAILABLE=$([bool]($null -ne $gdb))"
    Write-Output "BAREMETAL_I386_NM_AVAILABLE=$([bool]($null -ne $nm))"
    Write-Output 'BAREMETAL_I386_QEMU_VGA_CONSOLE_PROBE=skipped'
    return
}

if ($GdbPort -le 0) { $GdbPort = Resolve-FreeTcpPort }

if (-not $SkipBuild) {
    & $zig build baremetal-i386 -Doptimize=Debug -Dbaremetal-console-probe-banner=true --prefix $buildPrefix --summary all
    if ($LASTEXITCODE -ne 0) { throw "zig build baremetal-i386 console probe failed with exit code $LASTEXITCODE" }
}

$artifact = Join-Path $buildPrefix 'bin\openclaw-zig-baremetal-i386.elf'
if (-not (Test-Path $artifact)) { $artifact = Join-Path $repo 'zig-out\bin\openclaw-zig-baremetal-i386.elf' }
if (-not (Test-Path $artifact)) { throw "i386 VGA console artifact is missing: $artifact" }
$artifact = (Resolve-Path $artifact).Path

$symbolOutput = & $nm $artifact
if ($LASTEXITCODE -ne 0 -or $null -eq $symbolOutput -or $symbolOutput.Count -eq 0) {
    throw "Failed to resolve symbol table from $artifact using $nm"
}

$spinPauseAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[tT]\sbaremetal_main\.spinPause$' -SymbolName 'baremetal_main.spinPause'
$consoleStateAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[dDbB]\sbaremetal\.vga_text_console\.state$' -SymbolName 'baremetal.vga_text_console.state'
$artifactForGdb = $artifact.Replace('\', '/')
$gdbScript = Join-Path $releaseDir "qemu-i386-vga-console-probe-$runStamp.gdb"
$gdbStdout = Join-Path $releaseDir "qemu-i386-vga-console-probe-$runStamp.gdb.stdout.log"
$gdbStderr = Join-Path $releaseDir "qemu-i386-vga-console-probe-$runStamp.gdb.stderr.log"
$qemuStdout = Join-Path $releaseDir "qemu-i386-vga-console-probe-$runStamp.qemu.stdout.log"
$qemuStderr = Join-Path $releaseDir "qemu-i386-vga-console-probe-$runStamp.qemu.stderr.log"

$gdbTemplate = @'
set pagination off
set confirm off
set remotecache off
file __ARTIFACT__
target remote :__GDBPORT__
break *0x__SPINPAUSE__
commands
  silent
  printf "CONSOLE_MAGIC=%u\n", *(unsigned int*)(__CONSOLE_STATE_ADDR__ + __MAGIC_OFFSET__)
  printf "CONSOLE_API_VERSION=%u\n", *(unsigned short*)(__CONSOLE_STATE_ADDR__ + __API_VERSION_OFFSET__)
  printf "CONSOLE_COLS=%u\n", *(unsigned short*)(__CONSOLE_STATE_ADDR__ + __COLS_OFFSET__)
  printf "CONSOLE_ROWS=%u\n", *(unsigned short*)(__CONSOLE_STATE_ADDR__ + __ROWS_OFFSET__)
  printf "CONSOLE_CURSOR_ROW=%u\n", *(unsigned short*)(__CONSOLE_STATE_ADDR__ + __CURSOR_ROW_OFFSET__)
  printf "CONSOLE_CURSOR_COL=%u\n", *(unsigned short*)(__CONSOLE_STATE_ADDR__ + __CURSOR_COL_OFFSET__)
  printf "CONSOLE_BACKEND=%u\n", *(unsigned char*)(__CONSOLE_STATE_ADDR__ + __BACKEND_OFFSET__)
  printf "CONSOLE_WRITE_COUNT=%u\n", *(unsigned int*)(__CONSOLE_STATE_ADDR__ + __WRITE_COUNT_OFFSET__)
  printf "CONSOLE_CLEAR_COUNT=%u\n", *(unsigned int*)(__CONSOLE_STATE_ADDR__ + __CLEAR_COUNT_OFFSET__)
  printf "CONSOLE_PROBE_CELL0=%u\n", *(unsigned short*)(__VGA_BUFFER_ADDR__)
  printf "CONSOLE_PROBE_CELL1=%u\n", *(unsigned short*)(__VGA_BUFFER_ADDR__ + 2)
  quit
end
continue
'@

$gdbScriptContent = $gdbTemplate `
    -replace '__ARTIFACT__', $artifactForGdb `
    -replace '__GDBPORT__', $GdbPort `
    -replace '__SPINPAUSE__', $spinPauseAddress `
    -replace '__CONSOLE_STATE_ADDR__', ('0x' + $consoleStateAddress) `
    -replace '__VGA_BUFFER_ADDR__', $vgaBufferAddr `
    -replace '__MAGIC_OFFSET__', $consoleMagicOffset `
    -replace '__API_VERSION_OFFSET__', $consoleApiVersionOffset `
    -replace '__COLS_OFFSET__', $consoleColsOffset `
    -replace '__ROWS_OFFSET__', $consoleRowsOffset `
    -replace '__CURSOR_ROW_OFFSET__', $consoleCursorRowOffset `
    -replace '__CURSOR_COL_OFFSET__', $consoleCursorColOffset `
    -replace '__BACKEND_OFFSET__', $consoleBackendOffset `
    -replace '__WRITE_COUNT_OFFSET__', $consoleWriteCountOffset `
    -replace '__CLEAR_COUNT_OFFSET__', $consoleClearCountOffset
$gdbScriptContent | Set-Content -Path $gdbScript -Encoding ascii

Remove-PathWithRetry $gdbStdout
Remove-PathWithRetry $gdbStderr
Remove-PathWithRetry $qemuStdout
Remove-PathWithRetry $qemuStderr

$qemuArgs = @(
    '-kernel', $artifact,
    '-S',
    '-gdb', "tcp::$GdbPort",
    '-display', 'none',
    '-no-reboot',
    '-no-shutdown',
    '-serial', 'none',
    '-monitor', 'none',
    '-device', 'isa-debug-exit,iobase=0xf4,iosize=0x04'
)

$qemuPsi = New-Object System.Diagnostics.ProcessStartInfo
$qemuPsi.FileName = $qemu
$qemuPsi.UseShellExecute = $false
$qemuPsi.RedirectStandardOutput = $true
$qemuPsi.RedirectStandardError = $true
$qemuPsi.Arguments = (($qemuArgs | ForEach-Object {
    if ("$_" -match '[\s"]') { '"{0}"' -f (($_ -replace '"', '\"')) } else { "$_" }
}) -join ' ')

$qemuProc = New-Object System.Diagnostics.Process
$qemuProc.StartInfo = $qemuPsi
[void]$qemuProc.Start()
$qemuStdoutTask = $qemuProc.StandardOutput.ReadToEndAsync()
$qemuStderrTask = $qemuProc.StandardError.ReadToEndAsync()
Start-Sleep -Milliseconds 300

$gdbPsi = New-Object System.Diagnostics.ProcessStartInfo
$gdbPsi.FileName = $gdb
$gdbPsi.UseShellExecute = $false
$gdbPsi.RedirectStandardOutput = $true
$gdbPsi.RedirectStandardError = $true
$gdbPsi.Arguments = '--batch -x "' + $gdbScript + '"'

$gdbProc = New-Object System.Diagnostics.Process
$gdbProc.StartInfo = $gdbPsi
[void]$gdbProc.Start()
if (-not $gdbProc.WaitForExit($TimeoutSeconds * 1000)) {
    try { $gdbProc.Kill($true) } catch {}
    try { $qemuProc.Kill($true) } catch {}
    throw "GDB i386 VGA console probe timed out after $TimeoutSeconds seconds."
}

$gdbOutput = $gdbProc.StandardOutput.ReadToEnd()
$gdbError = $gdbProc.StandardError.ReadToEnd()
Set-Content -Path $gdbStdout -Value $gdbOutput -Encoding ascii
Set-Content -Path $gdbStderr -Value $gdbError -Encoding ascii

try {
    if (-not $qemuProc.HasExited) {
        try { $qemuProc.Kill() } catch {}
        if (-not $qemuProc.WaitForExit(5000)) {
            Stop-Process -Id $qemuProc.Id -Force -ErrorAction SilentlyContinue
            $qemuProc.WaitForExit()
        }
    }
} catch {}
$qemuOutput = $qemuStdoutTask.GetAwaiter().GetResult()
$qemuError = $qemuStderrTask.GetAwaiter().GetResult()
Set-Content -Path $qemuStdout -Value $qemuOutput -Encoding ascii
Set-Content -Path $qemuStderr -Value $qemuError -Encoding ascii

$magic = Extract-IntValue -Text $gdbOutput -Name 'CONSOLE_MAGIC'
$api = Extract-IntValue -Text $gdbOutput -Name 'CONSOLE_API_VERSION'
$cols = Extract-IntValue -Text $gdbOutput -Name 'CONSOLE_COLS'
$rows = Extract-IntValue -Text $gdbOutput -Name 'CONSOLE_ROWS'
$cursorRow = Extract-IntValue -Text $gdbOutput -Name 'CONSOLE_CURSOR_ROW'
$cursorCol = Extract-IntValue -Text $gdbOutput -Name 'CONSOLE_CURSOR_COL'
$backend = Extract-IntValue -Text $gdbOutput -Name 'CONSOLE_BACKEND'
$writeCount = Extract-IntValue -Text $gdbOutput -Name 'CONSOLE_WRITE_COUNT'
$clearCount = Extract-IntValue -Text $gdbOutput -Name 'CONSOLE_CLEAR_COUNT'
if ($magic -ne $consoleMagic) { throw "Unexpected console magic: $magic" }
if ($api -ne $apiVersion) { throw "Unexpected console API version: $api" }
if ($cols -ne $expectedCols -or $rows -ne $expectedRows) { throw "Unexpected console dimensions: ${cols}x${rows}" }
if ($cursorRow -ne 0 -or $cursorCol -ne 2) { throw "Unexpected console cursor position: row=$cursorRow col=$cursorCol" }
if ($backend -ne $consoleBackendVgaText) { throw "Unexpected console backend: $backend" }
if ($writeCount -ne 2 -or $clearCount -lt 1) { throw "Unexpected console counters: write=$writeCount clear=$clearCount" }

Write-Output 'BAREMETAL_I386_QEMU_AVAILABLE=True'
Write-Output "BAREMETAL_I386_QEMU_BINARY=$qemu"
Write-Output "BAREMETAL_I386_GDB_BINARY=$gdb"
Write-Output "BAREMETAL_I386_NM_BINARY=$nm"
Write-Output 'BAREMETAL_I386_QEMU_VGA_CONSOLE_PROBE=pass'
Write-Output "BAREMETAL_I386_QEMU_VGA_CONSOLE_MAGIC=$magic"
Write-Output "BAREMETAL_I386_QEMU_VGA_CONSOLE_BACKEND=$backend"
Write-Output "BAREMETAL_I386_QEMU_VGA_GDB_STDOUT=$gdbStdout"
Write-Output "BAREMETAL_I386_QEMU_VGA_GDB_STDERR=$gdbStderr"
Write-Output "BAREMETAL_I386_QEMU_VGA_QEMU_STDOUT=$qemuStdout"
Write-Output "BAREMETAL_I386_QEMU_VGA_QEMU_STDERR=$qemuStderr"
