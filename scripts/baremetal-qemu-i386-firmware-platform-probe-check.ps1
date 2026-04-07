# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 60,
    [int] $GdbPort = 0,
    [int] $MemoryMiB = 128
)

$ErrorActionPreference = "Stop"

$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$releaseDir = Join-Path $repo "release"
$runStamp = [DateTime]::UtcNow.ToString("yyyyMMddHHmmssfff")

$acpiMagic = 0x4f434150
$bootMemoryMagic = 0x4D454D42
$apiVersion = 2
$expectedExitCode = 0x80
$expectedMaskedVector = 200
$requiredAcpiFlags = 0x0E
$forbiddenAcpiFlags = 0x10
$expectedTotalBytes = [int64]$MemoryMiB * 1MB

$bootMemoryMagicOffset = 0
$bootMemoryApiVersionOffset = 4
$bootMemorySourceOffset = 6
$bootMemoryFlagsOffset = 8
$bootMemoryMemLowerKibOffset = 12
$bootMemoryMemUpperKibOffset = 16
$bootMemoryTotalBytesOffset = 20
$bootMemoryUsableBytesOffset = 28
$bootMemoryHeapBaseOffset = 36
$bootMemoryHeapLimitOffset = 44
$bootMemoryHeapSizeOffset = 52
$bootMemoryMmapEntryCountOffset = 60
$bootMemoryUsableRegionCountOffset = 64
$bootMemoryLargestUsableBaseOffset = 68
$bootMemoryLargestUsableSizeOffset = 76
$bootMemoryRegionEntryCountOffset = 84
$acpiMagicOffset = 0
$acpiApiVersionOffset = 4
$acpiPresentOffset = 6
$acpiRevisionOffset = 7
$acpiTableCountOffset = 14
$acpiLapicCountOffset = 16
$acpiIoApicCountOffset = 18
$acpiSciInterruptOffset = 20
$acpiPmTimerBlockOffset = 24
$acpiFlagsOffset = 28
$acpiRsdpAddrOffset = 32
$acpiRsdtAddrOffset = 40
$acpiXsdtAddrOffset = 48
$ioApicMagicOffset = 0
$ioApicApiVersionOffset = 4
$ioApicPresentOffset = 6
$ioApicAcpiPresentOffset = 7
$ioApicEnabledOffset = 8
$ioApicCountOffset = 12
$ioApicSelectedIndexOffset = 14
$ioApicRedirectionEntryCountOffset = 16
$ioApicIdOffset = 20
$ioApicVersionOffset = 24
$ioApicArbitrationIdOffset = 28
$ioApicGsiBaseOffset = 32
$ioApicMmioAddrOffset = 40
$timerEnabledOffset = 0
$timerPendingWakeCountOffset = 2
$timerDispatchCountOffset = 8
$timerLastInterruptCountOffset = 24
$timerTickQuantumOffset = 40
$interruptDescriptorReadyOffset = 0
$interruptDescriptorLoadedOffset = 1
$interruptLastVectorOffset = 2
$interruptCountOffset = 16
$interruptHistoryLenOffset = 56

function Resolve-ZigExecutable {
    $default = "C:\Users\Ady\Documents\toolchains\zig-master\current\zig.exe"
    if ($env:OPENCLAW_ZIG_BIN -and $env:OPENCLAW_ZIG_BIN.Trim().Length -gt 0) {
        if (-not (Test-Path $env:OPENCLAW_ZIG_BIN)) { throw "OPENCLAW_ZIG_BIN is set but not found: $($env:OPENCLAW_ZIG_BIN)" }
        return $env:OPENCLAW_ZIG_BIN
    }
    $cmd = Get-Command zig -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Path) { return $cmd.Path }
    if (Test-Path $default) { return $default }
    throw "Zig executable not found. Set OPENCLAW_ZIG_BIN or ensure zig is on PATH."
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

function Resolve-QemuExecutable { return Resolve-PreferredExecutable @("qemu-system-i386", "qemu-system-i386.exe", "C:\Program Files\qemu\qemu-system-i386.exe") }
function Resolve-GdbExecutable { return Resolve-PreferredExecutable @("gdb", "gdb.exe") }
function Resolve-NmExecutable { return Resolve-PreferredExecutable @("llvm-nm", "llvm-nm.exe", "nm", "nm.exe", "C:\Users\Ady\Documents\starpro\tooling\emsdk\upstream\bin\llvm-nm.exe") }

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
    Write-Output "BAREMETAL_I386_FIRMWARE_PLATFORM_PROBE=skipped"
    return
}

if ($GdbPort -le 0) { $GdbPort = Resolve-FreeTcpPort }

$gdbScript = Join-Path $releaseDir "qemu-i386-firmware-platform-probe-$runStamp.gdb"
$gdbStdout = Join-Path $releaseDir "qemu-i386-firmware-platform-probe-$runStamp.gdb.stdout.log"
$gdbStderr = Join-Path $releaseDir "qemu-i386-firmware-platform-probe-$runStamp.gdb.stderr.log"
$qemuStdout = Join-Path $releaseDir "qemu-i386-firmware-platform-probe-$runStamp.qemu.stdout.log"
$qemuStderr = Join-Path $releaseDir "qemu-i386-firmware-platform-probe-$runStamp.qemu.stderr.log"
$qemuDebug = Join-Path $releaseDir "qemu-i386-firmware-platform-probe-$runStamp.debug.log"
$firmwareImage = Join-Path $releaseDir "qemu-i386-firmware-platform-probe-$runStamp.img"
$firmwareMetadata = Join-Path $releaseDir "qemu-i386-firmware-platform-probe-$runStamp.meta.txt"

if (-not $SkipBuild) {
    & $zig build baremetal-i386 -Doptimize=Debug -Dbaremetal-i386-firmware-platform-probe=true --prefix $buildPrefix --summary all
    if ($LASTEXITCODE -ne 0) { throw "zig build baremetal-i386 firmware platform probe failed with exit code $LASTEXITCODE" }
}

$artifact = Join-Path $buildPrefix 'bin\openclaw-zig-baremetal-i386.elf'
if (-not (Test-Path $artifact)) { throw "i386 firmware platform-probe artifact not found at expected path: $artifact" }
$artifact = (Resolve-Path $artifact).Path

& (Join-Path $repo 'scripts\build-i386-firmware-image.ps1') `
    -ArtifactPath $artifact `
    -OutputImagePath $firmwareImage `
    -OutputMetadataPath $firmwareMetadata
if ($LASTEXITCODE -ne 0) { throw "i386 firmware image build failed with exit code $LASTEXITCODE" }

$symbolOutput = & $nm $artifact
if ($LASTEXITCODE -ne 0 -or $null -eq $symbolOutput -or $symbolOutput.Count -eq 0) {
    throw "Failed to resolve symbol table from $artifact using $nm"
}

$qemuExitAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[tT]\sbaremetal_main\.qemuExit$' -SymbolName "baremetal_main.qemuExit"
$bootMemoryStateAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[dDbB]\sbaremetal\.boot_memory\.state$' -SymbolName "baremetal.boot_memory.state"
$acpiStateAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[dDbB]\sbaremetal\.acpi\.state$' -SymbolName "baremetal.acpi.state"
$timerStateAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[dDbB]\sbaremetal_main\.timer_state$' -SymbolName "baremetal_main.timer_state"
$interruptStateAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[dDbB]\sbaremetal\.x86_bootstrap\.interrupt_state$' -SymbolName "baremetal.x86_bootstrap.interrupt_state"
$ioApicStateAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[dDbB]\sbaremetal\.ioapic\.state$' -SymbolName "baremetal.ioapic.state"
$maskedInterruptIgnoredCountAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[dDbB]\sbaremetal\.x86_bootstrap\.masked_interrupt_ignored_count$' -SymbolName "baremetal.x86_bootstrap.masked_interrupt_ignored_count"
$lastMaskedInterruptVectorAddress = Resolve-SymbolAddress -SymbolLines $symbolOutput -Pattern '\s[dDbB]\sbaremetal\.x86_bootstrap\.last_masked_interrupt_vector$' -SymbolName "baremetal.x86_bootstrap.last_masked_interrupt_vector"
$artifactForGdb = $artifact.Replace('\', '/')

Remove-PathWithRetry $gdbStdout
Remove-PathWithRetry $gdbStderr
Remove-PathWithRetry $qemuStdout
Remove-PathWithRetry $qemuStderr
Remove-PathWithRetry $qemuDebug

$gdbTemplate = @'
set pagination off
set confirm off
set remotecache off
file __ARTIFACT__
handle SIGQUIT nostop noprint pass
target remote :__GDBPORT__
break *0x__QEMU_EXIT__
commands
  silent
  printf "QEMU_EXIT_CODE_STACK=%u\n", *(unsigned int*)($esp + 4)
  printf "QEMU_EXIT_CODE_EAX=%u\n", (unsigned int)($eax & 0xff)
  printf "QEMU_EXIT_CODE_ECX=%u\n", (unsigned int)($ecx & 0xff)
  printf "BOOT_MEMORY_MAGIC=%u\n", *(unsigned int*)(__BOOT_MEMORY_STATE_ADDR__ + __BOOT_MEMORY_MAGIC_OFFSET__)
  printf "BOOT_MEMORY_API_VERSION=%u\n", *(unsigned short*)(__BOOT_MEMORY_STATE_ADDR__ + __BOOT_MEMORY_API_VERSION_OFFSET__)
  printf "BOOT_MEMORY_SOURCE=%u\n", *(unsigned char*)(__BOOT_MEMORY_STATE_ADDR__ + __BOOT_MEMORY_SOURCE_OFFSET__)
  printf "BOOT_MEMORY_FLAGS=%u\n", *(unsigned int*)(__BOOT_MEMORY_STATE_ADDR__ + __BOOT_MEMORY_FLAGS_OFFSET__)
  printf "BOOT_MEMORY_MEM_LOWER_KIB=%u\n", *(unsigned int*)(__BOOT_MEMORY_STATE_ADDR__ + __BOOT_MEMORY_MEM_LOWER_KIB_OFFSET__)
  printf "BOOT_MEMORY_MEM_UPPER_KIB=%u\n", *(unsigned int*)(__BOOT_MEMORY_STATE_ADDR__ + __BOOT_MEMORY_MEM_UPPER_KIB_OFFSET__)
  printf "BOOT_MEMORY_TOTAL_BYTES=%llu\n", *(unsigned long long*)(__BOOT_MEMORY_STATE_ADDR__ + __BOOT_MEMORY_TOTAL_BYTES_OFFSET__)
  printf "BOOT_MEMORY_USABLE_BYTES=%llu\n", *(unsigned long long*)(__BOOT_MEMORY_STATE_ADDR__ + __BOOT_MEMORY_USABLE_BYTES_OFFSET__)
  printf "BOOT_MEMORY_HEAP_BASE=%llu\n", *(unsigned long long*)(__BOOT_MEMORY_STATE_ADDR__ + __BOOT_MEMORY_HEAP_BASE_OFFSET__)
  printf "BOOT_MEMORY_HEAP_LIMIT=%llu\n", *(unsigned long long*)(__BOOT_MEMORY_STATE_ADDR__ + __BOOT_MEMORY_HEAP_LIMIT_OFFSET__)
  printf "BOOT_MEMORY_HEAP_SIZE=%llu\n", *(unsigned long long*)(__BOOT_MEMORY_STATE_ADDR__ + __BOOT_MEMORY_HEAP_SIZE_OFFSET__)
  printf "BOOT_MEMORY_MMAP_ENTRY_COUNT=%u\n", *(unsigned int*)(__BOOT_MEMORY_STATE_ADDR__ + __BOOT_MEMORY_MMAP_ENTRY_COUNT_OFFSET__)
  printf "BOOT_MEMORY_USABLE_REGION_COUNT=%u\n", *(unsigned int*)(__BOOT_MEMORY_STATE_ADDR__ + __BOOT_MEMORY_USABLE_REGION_COUNT_OFFSET__)
  printf "BOOT_MEMORY_LARGEST_USABLE_BASE=%llu\n", *(unsigned long long*)(__BOOT_MEMORY_STATE_ADDR__ + __BOOT_MEMORY_LARGEST_USABLE_BASE_OFFSET__)
  printf "BOOT_MEMORY_LARGEST_USABLE_SIZE=%llu\n", *(unsigned long long*)(__BOOT_MEMORY_STATE_ADDR__ + __BOOT_MEMORY_LARGEST_USABLE_SIZE_OFFSET__)
  printf "BOOT_MEMORY_REGION_ENTRY_COUNT=%u\n", *(unsigned int*)(__BOOT_MEMORY_STATE_ADDR__ + __BOOT_MEMORY_REGION_ENTRY_COUNT_OFFSET__)
  printf "ACPI_MAGIC=%u\n", *(unsigned int*)(__ACPI_STATE_ADDR__ + __ACPI_MAGIC_OFFSET__)
  printf "ACPI_API_VERSION=%u\n", *(unsigned short*)(__ACPI_STATE_ADDR__ + __ACPI_API_VERSION_OFFSET__)
  printf "ACPI_PRESENT=%u\n", *(unsigned char*)(__ACPI_STATE_ADDR__ + __ACPI_PRESENT_OFFSET__)
  printf "ACPI_REVISION=%u\n", *(unsigned char*)(__ACPI_STATE_ADDR__ + __ACPI_REVISION_OFFSET__)
  printf "ACPI_TABLE_COUNT=%u\n", *(unsigned short*)(__ACPI_STATE_ADDR__ + __ACPI_TABLE_COUNT_OFFSET__)
  printf "ACPI_LAPIC_COUNT=%u\n", *(unsigned short*)(__ACPI_STATE_ADDR__ + __ACPI_LAPIC_COUNT_OFFSET__)
  printf "ACPI_IOAPIC_COUNT=%u\n", *(unsigned short*)(__ACPI_STATE_ADDR__ + __ACPI_IOAPIC_COUNT_OFFSET__)
  printf "ACPI_SCI_INTERRUPT=%u\n", *(unsigned short*)(__ACPI_STATE_ADDR__ + __ACPI_SCI_INTERRUPT_OFFSET__)
  printf "ACPI_PM_TIMER_BLOCK=%u\n", *(unsigned int*)(__ACPI_STATE_ADDR__ + __ACPI_PM_TIMER_BLOCK_OFFSET__)
  printf "ACPI_FLAGS=%u\n", *(unsigned int*)(__ACPI_STATE_ADDR__ + __ACPI_FLAGS_OFFSET__)
  printf "ACPI_RSDP_ADDR=%u\n", *(unsigned int*)(__ACPI_STATE_ADDR__ + __ACPI_RSDP_ADDR_OFFSET__)
  printf "ACPI_RSDT_ADDR=%u\n", *(unsigned int*)(__ACPI_STATE_ADDR__ + __ACPI_RSDT_ADDR_OFFSET__)
  printf "ACPI_XSDT_ADDR=%llu\n", *(unsigned long long*)(__ACPI_STATE_ADDR__ + __ACPI_XSDT_ADDR_OFFSET__)
  printf "BDA_EBDA_SEGMENT=%u\n", *(unsigned short*)0x40e
  find /b 0xe0000, 0xfffff, 0x52, 0x53, 0x44, 0x20, 0x50, 0x54, 0x52, 0x20
  printf "RSDP_REVISION_DIRECT=%u\n", *(unsigned char*)(*(unsigned int*)(__ACPI_STATE_ADDR__ + __ACPI_RSDP_ADDR_OFFSET__) + 15)
  printf "RSDP_RSDT_DIRECT=%u\n", *(unsigned int*)(*(unsigned int*)(__ACPI_STATE_ADDR__ + __ACPI_RSDP_ADDR_OFFSET__) + 16)
  printf "RSDP_LENGTH_DIRECT=%u\n", *(unsigned int*)(*(unsigned int*)(__ACPI_STATE_ADDR__ + __ACPI_RSDP_ADDR_OFFSET__) + 20)
  printf "RSDP_XSDT_DIRECT=%llu\n", *(unsigned long long*)(*(unsigned int*)(__ACPI_STATE_ADDR__ + __ACPI_RSDP_ADDR_OFFSET__) + 24)
  printf "IOAPIC_MAGIC=%u\n", *(unsigned int*)(__IOAPIC_STATE_ADDR__ + __IOAPIC_MAGIC_OFFSET__)
  printf "IOAPIC_API_VERSION=%u\n", *(unsigned short*)(__IOAPIC_STATE_ADDR__ + __IOAPIC_API_VERSION_OFFSET__)
  printf "IOAPIC_PRESENT=%u\n", *(unsigned char*)(__IOAPIC_STATE_ADDR__ + __IOAPIC_PRESENT_OFFSET__)
  printf "IOAPIC_ACPI_PRESENT=%u\n", *(unsigned char*)(__IOAPIC_STATE_ADDR__ + __IOAPIC_ACPI_PRESENT_OFFSET__)
  printf "IOAPIC_ENABLED=%u\n", *(unsigned char*)(__IOAPIC_STATE_ADDR__ + __IOAPIC_ENABLED_OFFSET__)
  printf "IOAPIC_COUNT=%u\n", *(unsigned short*)(__IOAPIC_STATE_ADDR__ + __IOAPIC_COUNT_OFFSET__)
  printf "IOAPIC_SELECTED_INDEX=%u\n", *(unsigned short*)(__IOAPIC_STATE_ADDR__ + __IOAPIC_SELECTED_INDEX_OFFSET__)
  printf "IOAPIC_REDIRECTION_ENTRY_COUNT=%u\n", *(unsigned short*)(__IOAPIC_STATE_ADDR__ + __IOAPIC_REDIRECTION_ENTRY_COUNT_OFFSET__)
  printf "IOAPIC_ID=%u\n", *(unsigned int*)(__IOAPIC_STATE_ADDR__ + __IOAPIC_ID_OFFSET__)
  printf "IOAPIC_VERSION=%u\n", *(unsigned int*)(__IOAPIC_STATE_ADDR__ + __IOAPIC_VERSION_OFFSET__)
  printf "IOAPIC_ARBITRATION_ID=%u\n", *(unsigned int*)(__IOAPIC_STATE_ADDR__ + __IOAPIC_ARBITRATION_ID_OFFSET__)
  printf "IOAPIC_GSI_BASE=%u\n", *(unsigned int*)(__IOAPIC_STATE_ADDR__ + __IOAPIC_GSI_BASE_OFFSET__)
  printf "IOAPIC_MMIO_ADDR=%u\n", *(unsigned long long*)(__IOAPIC_STATE_ADDR__ + __IOAPIC_MMIO_ADDR_OFFSET__)
  printf "TIMER_ENABLED=%u\n", *(unsigned char*)(__TIMER_STATE_ADDR__ + __TIMER_ENABLED_OFFSET__)
  printf "TIMER_PENDING_WAKE_COUNT=%u\n", *(unsigned short*)(__TIMER_STATE_ADDR__ + __TIMER_PENDING_WAKE_COUNT_OFFSET__)
  printf "TIMER_DISPATCH_COUNT=%u\n", *(unsigned long long*)(__TIMER_STATE_ADDR__ + __TIMER_DISPATCH_COUNT_OFFSET__)
  printf "TIMER_LAST_INTERRUPT_COUNT=%u\n", *(unsigned long long*)(__TIMER_STATE_ADDR__ + __TIMER_LAST_INTERRUPT_COUNT_OFFSET__)
  printf "TIMER_TICK_QUANTUM=%u\n", *(unsigned int*)(__TIMER_STATE_ADDR__ + __TIMER_TICK_QUANTUM_OFFSET__)
  printf "INTERRUPT_DESCRIPTOR_READY=%u\n", *(unsigned char*)(__INTERRUPT_STATE_ADDR__ + __INTERRUPT_DESCRIPTOR_READY_OFFSET__)
  printf "INTERRUPT_DESCRIPTOR_LOADED=%u\n", *(unsigned char*)(__INTERRUPT_STATE_ADDR__ + __INTERRUPT_DESCRIPTOR_LOADED_OFFSET__)
  printf "INTERRUPT_LAST_VECTOR=%u\n", *(unsigned char*)(__INTERRUPT_STATE_ADDR__ + __INTERRUPT_LAST_VECTOR_OFFSET__)
  printf "INTERRUPT_COUNT=%u\n", *(unsigned long long*)(__INTERRUPT_STATE_ADDR__ + __INTERRUPT_COUNT_OFFSET__)
  printf "INTERRUPT_HISTORY_LEN=%u\n", *(unsigned int*)(__INTERRUPT_STATE_ADDR__ + __INTERRUPT_HISTORY_LEN_OFFSET__)
  printf "INTERRUPT_MASK_IGNORED_COUNT=%u\n", *(unsigned long long*)(__INTERRUPT_MASK_IGNORED_COUNT_ADDR__)
  printf "INTERRUPT_LAST_MASKED_VECTOR=%u\n", *(unsigned char*)(__INTERRUPT_LAST_MASKED_VECTOR_ADDR__)
  quit
end
continue
'@

$gdbScriptContent = $gdbTemplate `
    -replace '__ARTIFACT__', $artifactForGdb `
    -replace '__GDBPORT__', $GdbPort `
    -replace '__QEMU_EXIT__', $qemuExitAddress `
    -replace '__BOOT_MEMORY_STATE_ADDR__', ('0x' + $bootMemoryStateAddress) `
    -replace '__BOOT_MEMORY_MAGIC_OFFSET__', $bootMemoryMagicOffset `
    -replace '__BOOT_MEMORY_API_VERSION_OFFSET__', $bootMemoryApiVersionOffset `
    -replace '__BOOT_MEMORY_SOURCE_OFFSET__', $bootMemorySourceOffset `
    -replace '__BOOT_MEMORY_FLAGS_OFFSET__', $bootMemoryFlagsOffset `
    -replace '__BOOT_MEMORY_MEM_LOWER_KIB_OFFSET__', $bootMemoryMemLowerKibOffset `
    -replace '__BOOT_MEMORY_MEM_UPPER_KIB_OFFSET__', $bootMemoryMemUpperKibOffset `
    -replace '__BOOT_MEMORY_TOTAL_BYTES_OFFSET__', $bootMemoryTotalBytesOffset `
    -replace '__BOOT_MEMORY_USABLE_BYTES_OFFSET__', $bootMemoryUsableBytesOffset `
    -replace '__BOOT_MEMORY_HEAP_BASE_OFFSET__', $bootMemoryHeapBaseOffset `
    -replace '__BOOT_MEMORY_HEAP_LIMIT_OFFSET__', $bootMemoryHeapLimitOffset `
    -replace '__BOOT_MEMORY_HEAP_SIZE_OFFSET__', $bootMemoryHeapSizeOffset `
    -replace '__BOOT_MEMORY_MMAP_ENTRY_COUNT_OFFSET__', $bootMemoryMmapEntryCountOffset `
    -replace '__BOOT_MEMORY_USABLE_REGION_COUNT_OFFSET__', $bootMemoryUsableRegionCountOffset `
    -replace '__BOOT_MEMORY_LARGEST_USABLE_BASE_OFFSET__', $bootMemoryLargestUsableBaseOffset `
    -replace '__BOOT_MEMORY_LARGEST_USABLE_SIZE_OFFSET__', $bootMemoryLargestUsableSizeOffset `
    -replace '__BOOT_MEMORY_REGION_ENTRY_COUNT_OFFSET__', $bootMemoryRegionEntryCountOffset `
    -replace '__ACPI_STATE_ADDR__', ('0x' + $acpiStateAddress) `
    -replace '__IOAPIC_STATE_ADDR__', ('0x' + $ioApicStateAddress) `
    -replace '__TIMER_STATE_ADDR__', ('0x' + $timerStateAddress) `
    -replace '__INTERRUPT_STATE_ADDR__', ('0x' + $interruptStateAddress) `
    -replace '__INTERRUPT_MASK_IGNORED_COUNT_ADDR__', ('0x' + $maskedInterruptIgnoredCountAddress) `
    -replace '__INTERRUPT_LAST_MASKED_VECTOR_ADDR__', ('0x' + $lastMaskedInterruptVectorAddress) `
    -replace '__ACPI_MAGIC_OFFSET__', $acpiMagicOffset `
    -replace '__ACPI_API_VERSION_OFFSET__', $acpiApiVersionOffset `
    -replace '__ACPI_PRESENT_OFFSET__', $acpiPresentOffset `
    -replace '__ACPI_REVISION_OFFSET__', $acpiRevisionOffset `
    -replace '__ACPI_TABLE_COUNT_OFFSET__', $acpiTableCountOffset `
    -replace '__ACPI_LAPIC_COUNT_OFFSET__', $acpiLapicCountOffset `
    -replace '__ACPI_IOAPIC_COUNT_OFFSET__', $acpiIoApicCountOffset `
    -replace '__ACPI_SCI_INTERRUPT_OFFSET__', $acpiSciInterruptOffset `
    -replace '__ACPI_PM_TIMER_BLOCK_OFFSET__', $acpiPmTimerBlockOffset `
    -replace '__ACPI_FLAGS_OFFSET__', $acpiFlagsOffset `
    -replace '__ACPI_RSDP_ADDR_OFFSET__', $acpiRsdpAddrOffset `
    -replace '__ACPI_RSDT_ADDR_OFFSET__', $acpiRsdtAddrOffset `
    -replace '__ACPI_XSDT_ADDR_OFFSET__', $acpiXsdtAddrOffset `
    -replace '__IOAPIC_MAGIC_OFFSET__', $ioApicMagicOffset `
    -replace '__IOAPIC_API_VERSION_OFFSET__', $ioApicApiVersionOffset `
    -replace '__IOAPIC_PRESENT_OFFSET__', $ioApicPresentOffset `
    -replace '__IOAPIC_ACPI_PRESENT_OFFSET__', $ioApicAcpiPresentOffset `
    -replace '__IOAPIC_ENABLED_OFFSET__', $ioApicEnabledOffset `
    -replace '__IOAPIC_COUNT_OFFSET__', $ioApicCountOffset `
    -replace '__IOAPIC_SELECTED_INDEX_OFFSET__', $ioApicSelectedIndexOffset `
    -replace '__IOAPIC_REDIRECTION_ENTRY_COUNT_OFFSET__', $ioApicRedirectionEntryCountOffset `
    -replace '__IOAPIC_ID_OFFSET__', $ioApicIdOffset `
    -replace '__IOAPIC_VERSION_OFFSET__', $ioApicVersionOffset `
    -replace '__IOAPIC_ARBITRATION_ID_OFFSET__', $ioApicArbitrationIdOffset `
    -replace '__IOAPIC_GSI_BASE_OFFSET__', $ioApicGsiBaseOffset `
    -replace '__IOAPIC_MMIO_ADDR_OFFSET__', $ioApicMmioAddrOffset `
    -replace '__TIMER_ENABLED_OFFSET__', $timerEnabledOffset `
    -replace '__TIMER_PENDING_WAKE_COUNT_OFFSET__', $timerPendingWakeCountOffset `
    -replace '__TIMER_DISPATCH_COUNT_OFFSET__', $timerDispatchCountOffset `
    -replace '__TIMER_LAST_INTERRUPT_COUNT_OFFSET__', $timerLastInterruptCountOffset `
    -replace '__TIMER_TICK_QUANTUM_OFFSET__', $timerTickQuantumOffset `
    -replace '__INTERRUPT_DESCRIPTOR_READY_OFFSET__', $interruptDescriptorReadyOffset `
    -replace '__INTERRUPT_DESCRIPTOR_LOADED_OFFSET__', $interruptDescriptorLoadedOffset `
    -replace '__INTERRUPT_LAST_VECTOR_OFFSET__', $interruptLastVectorOffset `
    -replace '__INTERRUPT_COUNT_OFFSET__', $interruptCountOffset `
    -replace '__INTERRUPT_HISTORY_LEN_OFFSET__', $interruptHistoryLenOffset
$gdbScriptContent | Set-Content -Path $gdbScript -Encoding Ascii

$qemuProcess = $null
$gdbTimedOut = $false
try {
    $qemuArgs = @(
        "-M", "pc,accel=tcg,acpi=on",
        "-m", ("{0}M" -f $MemoryMiB),
        "-smp", "2",
        "-display", "none",
        "-serial", "none",
        "-monitor", "none",
        "-boot", "c",
        "-drive", "file=$firmwareImage,format=raw,if=ide,index=0,media=disk",
        "-global", "isa-debugcon.iobase=0xe9",
        "-debugcon", "file:$qemuDebug",
        "-no-reboot",
        "-no-shutdown",
        "-S",
        "-gdb", "tcp::$GdbPort",
        "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04"
    )
    $qemuProcess = Start-Process -FilePath $qemu -ArgumentList $qemuArgs -PassThru -RedirectStandardOutput $qemuStdout -RedirectStandardError $qemuStderr
    Start-Sleep -Milliseconds 600

    $gdbProcess = Start-Process -FilePath $gdb -ArgumentList @("-q", "-x", $gdbScript) -PassThru -RedirectStandardOutput $gdbStdout -RedirectStandardError $gdbStderr
    if (-not $gdbProcess.WaitForExit($TimeoutSeconds * 1000)) {
        $gdbTimedOut = $true
        try { $gdbProcess.Kill() } catch {}
    }

    if ($gdbTimedOut) { throw "gdb timed out after $TimeoutSeconds seconds" }
    $gdbExitCode = if ($null -eq $gdbProcess.ExitCode) { 0 } else { $gdbProcess.ExitCode }
    if ($gdbExitCode -ne 0) {
        $stderrTail = if (Test-Path $gdbStderr) { (Get-Content $gdbStderr -Tail 120) -join "`n" } else { "" }
        $debugTail = if (Test-Path $qemuDebug) { (Get-Content $qemuDebug -Tail 120) -join "`n" } else { "" }
        throw "gdb exited with code $gdbExitCode`n$stderrTail`n$debugTail"
    }
} finally {
    if ($qemuProcess -and -not $qemuProcess.HasExited) {
        try { $qemuProcess.Kill() } catch {}
        try { $qemuProcess.WaitForExit(2000) | Out-Null } catch {}
    }
}

$out = Get-Content -Path $gdbStdout -Raw
$exitCodeStack = Extract-IntValue -Text $out -Name 'QEMU_EXIT_CODE_STACK'
$exitCodeEax = Extract-IntValue -Text $out -Name 'QEMU_EXIT_CODE_EAX'
$exitCodeEcx = Extract-IntValue -Text $out -Name 'QEMU_EXIT_CODE_ECX'
$bootMemoryMagicValue = Extract-IntValue -Text $out -Name 'BOOT_MEMORY_MAGIC'
$bootMemoryApiVersionValue = Extract-IntValue -Text $out -Name 'BOOT_MEMORY_API_VERSION'
$bootMemorySourceValue = Extract-IntValue -Text $out -Name 'BOOT_MEMORY_SOURCE'
$bootMemoryFlagsValue = Extract-IntValue -Text $out -Name 'BOOT_MEMORY_FLAGS'
$bootMemoryMemLowerKibValue = Extract-IntValue -Text $out -Name 'BOOT_MEMORY_MEM_LOWER_KIB'
$bootMemoryMemUpperKibValue = Extract-IntValue -Text $out -Name 'BOOT_MEMORY_MEM_UPPER_KIB'
$bootMemoryTotalBytesValue = Extract-IntValue -Text $out -Name 'BOOT_MEMORY_TOTAL_BYTES'
$bootMemoryUsableBytesValue = Extract-IntValue -Text $out -Name 'BOOT_MEMORY_USABLE_BYTES'
$bootMemoryHeapBaseValue = Extract-IntValue -Text $out -Name 'BOOT_MEMORY_HEAP_BASE'
$bootMemoryHeapLimitValue = Extract-IntValue -Text $out -Name 'BOOT_MEMORY_HEAP_LIMIT'
$bootMemoryHeapSizeValue = Extract-IntValue -Text $out -Name 'BOOT_MEMORY_HEAP_SIZE'
$bootMemoryMmapEntryCountValue = Extract-IntValue -Text $out -Name 'BOOT_MEMORY_MMAP_ENTRY_COUNT'
$bootMemoryUsableRegionCountValue = Extract-IntValue -Text $out -Name 'BOOT_MEMORY_USABLE_REGION_COUNT'
$bootMemoryLargestUsableBaseValue = Extract-IntValue -Text $out -Name 'BOOT_MEMORY_LARGEST_USABLE_BASE'
$bootMemoryLargestUsableSizeValue = Extract-IntValue -Text $out -Name 'BOOT_MEMORY_LARGEST_USABLE_SIZE'
$bootMemoryRegionEntryCountValue = Extract-IntValue -Text $out -Name 'BOOT_MEMORY_REGION_ENTRY_COUNT'
$acpiMagicValue = Extract-IntValue -Text $out -Name 'ACPI_MAGIC'
$acpiApiVersionValue = Extract-IntValue -Text $out -Name 'ACPI_API_VERSION'
$acpiPresentValue = Extract-IntValue -Text $out -Name 'ACPI_PRESENT'
$acpiRevisionValue = Extract-IntValue -Text $out -Name 'ACPI_REVISION'
$acpiTableCountValue = Extract-IntValue -Text $out -Name 'ACPI_TABLE_COUNT'
$acpiLapicCountValue = Extract-IntValue -Text $out -Name 'ACPI_LAPIC_COUNT'
$acpiIoApicCountValue = Extract-IntValue -Text $out -Name 'ACPI_IOAPIC_COUNT'
$acpiSciInterruptValue = Extract-IntValue -Text $out -Name 'ACPI_SCI_INTERRUPT'
$acpiPmTimerBlockValue = Extract-IntValue -Text $out -Name 'ACPI_PM_TIMER_BLOCK'
$acpiFlagsValue = Extract-IntValue -Text $out -Name 'ACPI_FLAGS'
$acpiRsdpAddrValue = Extract-IntValue -Text $out -Name 'ACPI_RSDP_ADDR'
$acpiRsdtAddrValue = Extract-IntValue -Text $out -Name 'ACPI_RSDT_ADDR'
$acpiXsdtAddrValue = Extract-IntValue -Text $out -Name 'ACPI_XSDT_ADDR'
$ioApicMagicValue = Extract-IntValue -Text $out -Name 'IOAPIC_MAGIC'
$ioApicApiVersionValue = Extract-IntValue -Text $out -Name 'IOAPIC_API_VERSION'
$ioApicPresentValue = Extract-IntValue -Text $out -Name 'IOAPIC_PRESENT'
$ioApicAcpiPresentValue = Extract-IntValue -Text $out -Name 'IOAPIC_ACPI_PRESENT'
$ioApicEnabledValue = Extract-IntValue -Text $out -Name 'IOAPIC_ENABLED'
$ioApicCountValue = Extract-IntValue -Text $out -Name 'IOAPIC_COUNT'
$ioApicSelectedIndexValue = Extract-IntValue -Text $out -Name 'IOAPIC_SELECTED_INDEX'
$ioApicRedirectionEntryCountValue = Extract-IntValue -Text $out -Name 'IOAPIC_REDIRECTION_ENTRY_COUNT'
$ioApicIdValue = Extract-IntValue -Text $out -Name 'IOAPIC_ID'
$ioApicVersionValue = Extract-IntValue -Text $out -Name 'IOAPIC_VERSION'
$ioApicArbitrationIdValue = Extract-IntValue -Text $out -Name 'IOAPIC_ARBITRATION_ID'
$ioApicGsiBaseValue = Extract-IntValue -Text $out -Name 'IOAPIC_GSI_BASE'
$ioApicMmioAddrValue = Extract-IntValue -Text $out -Name 'IOAPIC_MMIO_ADDR'
$timerEnabledValue = Extract-IntValue -Text $out -Name 'TIMER_ENABLED'
$timerPendingWakeCountValue = Extract-IntValue -Text $out -Name 'TIMER_PENDING_WAKE_COUNT'
$timerDispatchCountValue = Extract-IntValue -Text $out -Name 'TIMER_DISPATCH_COUNT'
$timerLastInterruptCountValue = Extract-IntValue -Text $out -Name 'TIMER_LAST_INTERRUPT_COUNT'
$timerTickQuantumValue = Extract-IntValue -Text $out -Name 'TIMER_TICK_QUANTUM'
$interruptDescriptorReadyValue = Extract-IntValue -Text $out -Name 'INTERRUPT_DESCRIPTOR_READY'
$interruptDescriptorLoadedValue = Extract-IntValue -Text $out -Name 'INTERRUPT_DESCRIPTOR_LOADED'
$interruptLastVectorValue = Extract-IntValue -Text $out -Name 'INTERRUPT_LAST_VECTOR'
$interruptCountValue = Extract-IntValue -Text $out -Name 'INTERRUPT_COUNT'
$interruptHistoryLenValue = Extract-IntValue -Text $out -Name 'INTERRUPT_HISTORY_LEN'
$interruptMaskIgnoredCountValue = Extract-IntValue -Text $out -Name 'INTERRUPT_MASK_IGNORED_COUNT'
$interruptLastMaskedVectorValue = Extract-IntValue -Text $out -Name 'INTERRUPT_LAST_MASKED_VECTOR'

Write-Output "BAREMETAL_I386_QEMU_AVAILABLE=True"
Write-Output "BAREMETAL_I386_GDB_AVAILABLE=True"
Write-Output "BAREMETAL_I386_NM_AVAILABLE=True"
Write-Output "BAREMETAL_I386_QEMU_BINARY=$qemu"
Write-Output "BAREMETAL_I386_GDB_BINARY=$gdb"
Write-Output "BAREMETAL_I386_NM_BINARY=$nm"
Write-Output "BAREMETAL_I386_QEMU_ARTIFACT=$artifact"
Write-Output "BAREMETAL_I386_FIRMWARE_IMAGE=$firmwareImage"
Write-Output "BAREMETAL_I386_FIRMWARE_METADATA=$firmwareMetadata"
Write-Output "BAREMETAL_I386_FIRMWARE_PLATFORM_PROBE_MEMORY_MIB=$MemoryMiB"
Write-Output "BAREMETAL_I386_FIRMWARE_PLATFORM_PROBE_EXIT_CODE_STACK=$exitCodeStack"
Write-Output "BAREMETAL_I386_FIRMWARE_PLATFORM_PROBE_EXIT_CODE_EAX=$exitCodeEax"
Write-Output "BAREMETAL_I386_FIRMWARE_PLATFORM_PROBE_EXIT_CODE_ECX=$exitCodeEcx"
Write-Output "BAREMETAL_I386_FIRMWARE_PLATFORM_PROBE_BOOT_MEMORY_SOURCE=$bootMemorySourceValue"
Write-Output "BAREMETAL_I386_FIRMWARE_PLATFORM_PROBE_BOOT_MEMORY_FLAGS=$bootMemoryFlagsValue"
Write-Output "BAREMETAL_I386_FIRMWARE_PLATFORM_PROBE_BOOT_MEMORY_MEM_LOWER_KIB=$bootMemoryMemLowerKibValue"
Write-Output "BAREMETAL_I386_FIRMWARE_PLATFORM_PROBE_BOOT_MEMORY_MEM_UPPER_KIB=$bootMemoryMemUpperKibValue"
Write-Output "BAREMETAL_I386_FIRMWARE_PLATFORM_PROBE_BOOT_MEMORY_TOTAL_BYTES=$bootMemoryTotalBytesValue"
Write-Output "BAREMETAL_I386_FIRMWARE_PLATFORM_PROBE_BOOT_MEMORY_USABLE_BYTES=$bootMemoryUsableBytesValue"
Write-Output "BAREMETAL_I386_FIRMWARE_PLATFORM_PROBE_BOOT_MEMORY_HEAP_BASE=$bootMemoryHeapBaseValue"
Write-Output "BAREMETAL_I386_FIRMWARE_PLATFORM_PROBE_BOOT_MEMORY_HEAP_LIMIT=$bootMemoryHeapLimitValue"
Write-Output "BAREMETAL_I386_FIRMWARE_PLATFORM_PROBE_BOOT_MEMORY_HEAP_SIZE=$bootMemoryHeapSizeValue"
Write-Output "BAREMETAL_I386_FIRMWARE_PLATFORM_PROBE_BOOT_MEMORY_MMAP_ENTRY_COUNT=$bootMemoryMmapEntryCountValue"
Write-Output "BAREMETAL_I386_FIRMWARE_PLATFORM_PROBE_BOOT_MEMORY_USABLE_REGION_COUNT=$bootMemoryUsableRegionCountValue"
Write-Output "BAREMETAL_I386_FIRMWARE_PLATFORM_PROBE_BOOT_MEMORY_LARGEST_USABLE_BASE=$bootMemoryLargestUsableBaseValue"
Write-Output "BAREMETAL_I386_FIRMWARE_PLATFORM_PROBE_BOOT_MEMORY_LARGEST_USABLE_SIZE=$bootMemoryLargestUsableSizeValue"
Write-Output "BAREMETAL_I386_FIRMWARE_PLATFORM_PROBE_BOOT_MEMORY_REGION_ENTRY_COUNT=$bootMemoryRegionEntryCountValue"
Write-Output "BAREMETAL_I386_FIRMWARE_PLATFORM_PROBE_ACPI_PRESENT=$acpiPresentValue"
Write-Output "BAREMETAL_I386_FIRMWARE_PLATFORM_PROBE_ACPI_TABLE_COUNT=$acpiTableCountValue"
Write-Output "BAREMETAL_I386_FIRMWARE_PLATFORM_PROBE_ACPI_LAPIC_COUNT=$acpiLapicCountValue"
Write-Output "BAREMETAL_I386_FIRMWARE_PLATFORM_PROBE_ACPI_IOAPIC_COUNT=$acpiIoApicCountValue"
Write-Output "BAREMETAL_I386_FIRMWARE_PLATFORM_PROBE_ACPI_SCI_INTERRUPT=$acpiSciInterruptValue"
Write-Output "BAREMETAL_I386_FIRMWARE_PLATFORM_PROBE_ACPI_FLAGS=$acpiFlagsValue"
Write-Output "BAREMETAL_I386_FIRMWARE_PLATFORM_PROBE_ACPI_RSDT_ADDR=$acpiRsdtAddrValue"
Write-Output "BAREMETAL_I386_FIRMWARE_PLATFORM_PROBE_ACPI_XSDT_ADDR=$acpiXsdtAddrValue"
Write-Output "BAREMETAL_I386_FIRMWARE_PLATFORM_PROBE_IOAPIC_PRESENT=$ioApicPresentValue"
Write-Output "BAREMETAL_I386_FIRMWARE_PLATFORM_PROBE_IOAPIC_COUNT=$ioApicCountValue"
Write-Output "BAREMETAL_I386_FIRMWARE_PLATFORM_PROBE_IOAPIC_REDIRECTION_ENTRY_COUNT=$ioApicRedirectionEntryCountValue"
Write-Output "BAREMETAL_I386_FIRMWARE_PLATFORM_PROBE_IOAPIC_MMIO_ADDR=$ioApicMmioAddrValue"
Write-Output "BAREMETAL_I386_FIRMWARE_PLATFORM_PROBE_TIMER_DISPATCH_COUNT=$timerDispatchCountValue"
Write-Output "BAREMETAL_I386_FIRMWARE_PLATFORM_PROBE_TIMER_PENDING_WAKE_COUNT=$timerPendingWakeCountValue"
Write-Output "BAREMETAL_I386_FIRMWARE_PLATFORM_PROBE_INTERRUPT_MASK_IGNORED_COUNT=$interruptMaskIgnoredCountValue"
Write-Output "BAREMETAL_I386_FIRMWARE_PLATFORM_PROBE_INTERRUPT_LAST_MASKED_VECTOR=$interruptLastMaskedVectorValue"

$pass = (
    $bootMemoryMagicValue -eq $bootMemoryMagic -and
    $bootMemoryApiVersionValue -eq $apiVersion -and
    $bootMemorySourceValue -eq 1 -and
    (($bootMemoryFlagsValue -band 0xB) -eq 0xB) -and
    $bootMemoryMemLowerKibValue -ge 639 -and
    $bootMemoryMemUpperKibValue -gt 0 -and
    $bootMemoryTotalBytesValue -ge $expectedTotalBytes -and
    $bootMemoryUsableBytesValue -gt 0 -and
    $bootMemoryUsableBytesValue -le $bootMemoryTotalBytesValue -and
    $bootMemoryHeapBaseValue -ge 0x00100000 -and
    $bootMemoryHeapLimitValue -gt $bootMemoryHeapBaseValue -and
    $bootMemoryHeapSizeValue -gt 0 -and
    $bootMemoryHeapLimitValue -le $bootMemoryTotalBytesValue -and
    $bootMemoryMmapEntryCountValue -ge 0 -and
    $bootMemoryUsableRegionCountValue -ge 0 -and
    $bootMemoryLargestUsableBaseValue -ge 0 -and
    $bootMemoryLargestUsableSizeValue -gt 0 -and
    $bootMemoryRegionEntryCountValue -ge 1 -and
    (($bootMemoryFlagsValue -band 0x80) -eq 0x80) -and
    (($bootMemoryFlagsValue -band 0x4) -eq 0x4) -and
    (($bootMemoryFlagsValue -band 0x40) -eq 0) -and
    $acpiMagicValue -eq $acpiMagic -and
    $acpiApiVersionValue -eq $apiVersion -and
    $acpiPresentValue -eq 1 -and
    $acpiRevisionValue -ge 0 -and
    $acpiTableCountValue -ge 2 -and
    $acpiLapicCountValue -ge 1 -and
    $acpiIoApicCountValue -ge 1 -and
    $acpiSciInterruptValue -gt 0 -and
    $acpiPmTimerBlockValue -gt 0 -and
    (($acpiFlagsValue -band $requiredAcpiFlags) -eq $requiredAcpiFlags) -and
    (($acpiFlagsValue -band $forbiddenAcpiFlags) -eq 0) -and
    $acpiRsdpAddrValue -gt 0 -and
    ($acpiRsdtAddrValue -gt 0 -or $acpiXsdtAddrValue -gt 0) -and
    $ioApicMagicValue -eq 0x4f434950 -and
    $ioApicApiVersionValue -eq $apiVersion -and
    $ioApicPresentValue -eq 1 -and
    $ioApicAcpiPresentValue -eq 1 -and
    $ioApicEnabledValue -eq 1 -and
    $ioApicCountValue -ge 1 -and
    $ioApicSelectedIndexValue -eq 0 -and
    $ioApicRedirectionEntryCountValue -gt 0 -and
    $ioApicIdValue -ge 0 -and
    $ioApicVersionValue -gt 0 -and
    $ioApicArbitrationIdValue -ge 0 -and
    $ioApicGsiBaseValue -ge 0 -and
    $ioApicMmioAddrValue -gt 0 -and
    $timerEnabledValue -eq 1 -and
    $timerPendingWakeCountValue -eq 1 -and
    $timerDispatchCountValue -eq 0 -and
    $timerLastInterruptCountValue -eq 0 -and
    $timerTickQuantumValue -eq 1 -and
    $interruptDescriptorReadyValue -eq 1 -and
    $interruptDescriptorLoadedValue -eq 1 -and
    $interruptLastVectorValue -eq 0 -and
    $interruptCountValue -eq 0 -and
    $interruptHistoryLenValue -eq 1 -and
    $interruptMaskIgnoredCountValue -eq 1 -and
    $interruptLastMaskedVectorValue -eq $expectedMaskedVector
)

Write-Output ("BAREMETAL_I386_FIRMWARE_PLATFORM_PROBE_REAL_ACPI_USED={0}" -f (($acpiFlagsValue -band $requiredAcpiFlags) -eq $requiredAcpiFlags))
Write-Output "BAREMETAL_I386_FIRMWARE_PLATFORM_PROBE_PASS=$pass"
if (-not $pass) {
    $debugTail = if (Test-Path $qemuDebug) { (Get-Content $qemuDebug -Tail 120) -join "`n" } else { "" }
    throw "i386 firmware platform probe validation failed.`n$out`n$debugTail"
}
