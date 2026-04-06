const mounted_external_fs = @import("baremetal/mounted_external_fs.zig");
const mount_table = @import("baremetal/mount_table.zig");
const virtual_fs = @import("baremetal/virtual_fs.zig");
const package_store = @import("baremetal/package_store.zig");
const BaremetalMountInfo = abi.BaremetalMountInfo;
const BaremetalKeyboardState = abi.BaremetalKeyboardState;
const BaremetalKeyboardEvent = abi.BaremetalKeyboardEvent;
const BaremetalMouseState = abi.BaremetalMouseState;
const BaremetalMousePacket = abi.BaremetalMousePacket;
const BaremetalCommandEvent = abi.BaremetalCommandEvent;
const BaremetalHealthEvent = abi.BaremetalHealthEvent;
const BaremetalModeEvent = abi.BaremetalModeEvent;
const BaremetalBootPhaseEvent = abi.BaremetalBootPhaseEvent;
const BaremetalCommandResultCounters = abi.BaremetalCommandResultCounters;
const BaremetalSchedulerState = abi.BaremetalSchedulerState;
const BaremetalTask = abi.BaremetalTask;
const BaremetalAllocatorState = abi.BaremetalAllocatorState;
const BaremetalAllocationRecord = abi.BaremetalAllocationRecord;
const BaremetalSyscallState = abi.BaremetalSyscallState;
const BaremetalSyscallEntry = abi.BaremetalSyscallEntry;
const BaremetalTimerState = abi.BaremetalTimerState;
const BaremetalTimerEntry = abi.BaremetalTimerEntry;
const BaremetalWakeEvent = abi.BaremetalWakeEvent;
const BaremetalWakeQueueSummary = abi.BaremetalWakeQueueSummary;
const BaremetalWakeQueueAgeBuckets = abi.BaremetalWakeQueueAgeBuckets;
const BaremetalWakeQueueCountQuery = extern struct {
    vector: u8,
    reason: u8,
    reserved0: u16,
    reserved1: u32,
    max_tick: u64,
};
const qemu_virtio_block_mount_probe_ok_code: u8 = 0x5A;
const qemu_virtio_block_ext2_mount_probe_ok_code: u8 = 0x5B;
const qemu_virtio_block_fat32_mount_probe_ok_code: u8 = 0x5C;
const qemu_virtio_block_mount_control_probe_ok_code: u8 = 0x5D;
        pub const virtio_block_mount_probe: bool = false;
        pub const virtio_block_ext2_mount_probe: bool = false;
        pub const virtio_block_fat32_mount_probe: bool = false;
        pub const virtio_block_mount_control_probe: bool = false;
const virtio_block_mount_probe_enabled: bool = if (@hasDecl(build_options, "virtio_block_mount_probe")) build_options.virtio_block_mount_probe else false;
const virtio_block_ext2_mount_probe_enabled: bool = if (@hasDecl(build_options, "virtio_block_ext2_mount_probe")) build_options.virtio_block_ext2_mount_probe else false;
const virtio_block_fat32_mount_probe_enabled: bool = if (@hasDecl(build_options, "virtio_block_fat32_mount_probe")) build_options.virtio_block_fat32_mount_probe else false;
const virtio_block_mount_control_probe_enabled: bool = if (@hasDecl(build_options, "virtio_block_mount_control_probe")) build_options.virtio_block_mount_control_probe else false;
const virtio_block_probe_filesystem_path = "/runtime/state/virtio-block.json";
const virtio_block_probe_filesystem_payload = "{\"disk\":\"virtio-block\"}";

const AtaStorageProbeError = error{
    AtaBackendUnavailable,
    PartitionMountMismatch,
    RawPatternWriteFailed,
    RawPatternFlushFailed,
    RawPatternReadbackFailed,
    PartitionExportMismatch,
    SecondaryRawPatternWriteFailed,
    SecondaryRawPatternReadbackFailed,
    ToolLayoutInitFailed,
    ToolLayoutFormatFailed,
    ToolLayoutWriteFailed,
    ToolLayoutReadbackFailed,
    ToolLayoutReloadFailed,
    FilesystemInitFailed,
    FilesystemFormatFailed,
    FilesystemDirCreateFailed,
    FilesystemWriteFailed,
    FilesystemReadbackFailed,
    FilesystemReloadFailed,
};

const AtaGptInstallerProbeError = error{
    AtaBackendUnavailable,
    PartitionMountMismatch,
    RawPatternWriteFailed,
    RawPatternFlushFailed,
    RawPatternReadbackFailed,
    InstallerFailed,
    LoaderCfgReadbackFailed,
    KernelInfoReadbackFailed,
    ManifestReadbackFailed,
    PackageListFailed,
const VirtioBlockMountProbeError = error{
    BackendUnavailable,
    BootMountBindFailed,
    RuntimeMountBindFailed,
    CacheMountBindFailed,
    BootMountRemoveFailed,
    MountExportMismatch,
    BootAliasTargetMismatch,
    RuntimeAliasTargetMismatch,
    CacheAliasTargetMismatch,
    LoaderAliasReadbackFailed,
    RuntimeAliasWriteFailed,
    CacheAliasWriteFailed,
    RootVfsListingMismatch,
    ProcVersionReadbackFailed,
    StorageStateReadFailed,
    StorageStateBackendMismatch,
    StorageStateFilesystemMismatch,
    StorageBackendRegistryReadbackFailed,
    StorageFilesystemMatrixReadbackFailed,
    StorageRegistryReadbackFailed,
    RuntimeAliasReloadFailed,
    TmpfsAliasVolatilityMismatch,
    PciDiscoveryMismatch,
};

const VirtioBlockExt2MountProbeError = error{
    BackendUnavailable,
    ExternalAliasMountExportMismatch,
    ExternalAliasListingFailed,
    ExternalAliasReadbackFailed,
    ExternalAliasStatFailed,
    ReadOnlyWriteMismatch,
    FilesystemMatrixReadbackFailed,
    StorageRegistryReadbackFailed,
    BackendRegistryReadbackFailed,
    PciDiscoveryMismatch,
};

const VirtioBlockFat32MountProbeError = error{
    BackendUnavailable,
    ExternalAliasMountExportMismatch,
    ExternalAliasListingFailed,
    ExternalAliasReadbackFailed,
    ExternalAliasStatFailed,
    ExternalAliasWriteFailed,
    ExternalAliasOverwriteFailed,
    ExternalAliasDeleteFailed,
    NestedAliasListingFailed,
    NestedAliasReadbackFailed,
    NestedAliasWriteFailed,
    NestedAliasOverwriteFailed,
    NestedAliasDeleteFailed,
    DirectoryAliasCreateFailed,
    DirectoryAliasReadbackFailed,
    DirectoryAliasWriteFailed,
    DirectoryAliasDeleteFailed,
    NestedDirectoryAliasCreateFailed,
    NestedDirectoryAliasDeleteFailed,
    FilesystemMatrixReadbackFailed,
    StorageRegistryReadbackFailed,
    BackendRegistryReadbackFailed,
    PciDiscoveryMismatch,
};

const VirtioBlockMountControlProbeError = error{
    BackendUnavailable,
    MountBindFailed,
    MountExportMismatch,
    MountListReadFailed,
    MountInfoReadFailed,
    AliasWriteFailed,
    AliasReadbackFailed,
    ReloadFailed,
    MountRemoveFailed,
    PciDiscoveryMismatch,
};

pub export fn oc_filesystem_mount_count() u32 {
    return @as(u32, @intCast(filesystem.mountCount()));
}

pub export fn oc_filesystem_mount_entry(index: u32) BaremetalMountInfo {
    if (index > std.math.maxInt(usize)) return std.mem.zeroes(BaremetalMountInfo);
    const entry = filesystem.mountEntry(@as(usize, @intCast(index))) orelse {
        return std.mem.zeroes(BaremetalMountInfo);
    };
    return mountInfoFromEntry(entry);
}

pub export fn oc_filesystem_bind_mount(name_ptr: [*]const u8, name_len: u32, target_ptr: [*]const u8, target_len: u32, tick: u64) i16 {
    var name_buf: [mount_table.max_name_len]u8 = undefined;
    var target_buf: [mount_table.max_target_len]u8 = undefined;
    const name = copyInputBytes(name_ptr, name_len, name_buf[0..]) orelse return abi.result_invalid_argument;
    const target = copyInputBytes(target_ptr, target_len, target_buf[0..]) orelse return abi.result_invalid_argument;
pub export fn oc_filesystem_remove_mount(name_ptr: [*]const u8, name_len: u32, tick: u64) i16 {
    var name_buf: [mount_table.max_name_len]u8 = undefined;
    const name = copyInputBytes(name_ptr, name_len, name_buf[0..]) orelse return abi.result_invalid_argument;
    if (virtio_block_mount_probe_enabled) {
        runVirtioBlockMountProbe() catch |err| qemuExit(virtioBlockMountProbeFailureCode(err));
        qemuExit(qemu_virtio_block_mount_probe_ok_code);
    }
    if (virtio_block_ext2_mount_probe_enabled) {
        runVirtioBlockExt2MountProbe() catch |err| qemuExit(virtioBlockExt2MountProbeFailureCode(err));
        qemuExit(qemu_virtio_block_ext2_mount_probe_ok_code);
    }
    if (virtio_block_fat32_mount_probe_enabled) {
        runVirtioBlockFat32MountProbe() catch |err| qemuExit(virtioBlockFat32MountProbeFailureCode(err));
        qemuExit(qemu_virtio_block_fat32_mount_probe_ok_code);
    }
    if (virtio_block_mount_control_probe_enabled) {
        runVirtioBlockMountControlProbe() catch |err| qemuExit(virtioBlockMountControlProbeFailureCode(err));
        qemuExit(qemu_virtio_block_mount_control_probe_ok_code);
    }
    if (storage.backend != abi.storage_backend_ata_pio or storage.mounted == 0) {
        return error.AtaBackendUnavailable;
    }
    if (storage.block_count <= ata_probe_raw_lba + ata_probe_raw_block_count) {
        return error.PartitionMountMismatch;
    }
    if (oc_storage_partition_count() != 2 or oc_storage_selected_partition_index() != 0) {
        return error.PartitionExportMismatch;
    }
    const primary_partition = oc_storage_partition_info(0);
    const secondary_partition = oc_storage_partition_info(1);
    if (primary_partition.scheme != @intFromEnum(ata_pio_disk.PartitionScheme.mbr) or
        primary_partition.start_lba != ata_probe_partition_start_lba or
        primary_partition.sector_count != ata_probe_partition_sector_count or
        secondary_partition.scheme != @intFromEnum(ata_pio_disk.PartitionScheme.mbr) or
        secondary_partition.start_lba != ata_probe_secondary_partition_start_lba or
        secondary_partition.sector_count != ata_probe_secondary_partition_sector_count)
    {
        return error.PartitionExportMismatch;
    }

    if (oc_storage_write_pattern(ata_probe_raw_lba, ata_probe_raw_block_count, ata_probe_raw_seed) != abi.result_ok) {
        return error.RawPatternWriteFailed;
    }
    if (oc_storage_flush() != abi.result_ok) {
        return error.RawPatternFlushFailed;
    }
    if (oc_storage_read_byte(ata_probe_raw_lba, 0) != ata_probe_raw_seed or
        oc_storage_read_byte(ata_probe_raw_lba, 1) != ata_probe_raw_seed +% 1 or
        oc_storage_read_byte(ata_probe_raw_lba + 1, 0) != ata_probe_raw_seed)
    {
        return error.RawPatternReadbackFailed;
    }

    if (oc_storage_select_partition(1) != abi.result_ok) {
        return error.PartitionExportMismatch;
    }
    if (oc_storage_logical_base_lba() != ata_probe_secondary_partition_start_lba or
        oc_storage_selected_partition_index() != 1 or
        storage_backend.statePtr().block_count != ata_probe_secondary_partition_sector_count)
    {
        return error.PartitionExportMismatch;
    }
    if (oc_storage_write_pattern(ata_probe_secondary_raw_lba, 1, ata_probe_secondary_raw_seed) != abi.result_ok) {
        return error.SecondaryRawPatternWriteFailed;
    }
    if (oc_storage_flush() != abi.result_ok) {
        return error.RawPatternFlushFailed;
    }
    if (oc_storage_read_byte(ata_probe_secondary_raw_lba, 0) != ata_probe_secondary_raw_seed or
        oc_storage_read_byte(ata_probe_secondary_raw_lba, 1) != ata_probe_secondary_raw_seed +% 1)
    {
        return error.SecondaryRawPatternReadbackFailed;
    }

    if (oc_storage_select_partition(0) != abi.result_ok) {
        return error.PartitionExportMismatch;
    }
    if (oc_storage_logical_base_lba() != ata_probe_partition_start_lba or
        oc_storage_selected_partition_index() != 0 or
        storage_backend.statePtr().block_count != ata_probe_partition_sector_count)
    {
        return error.PartitionExportMismatch;
    }

    if (oc_tool_layout_init() != abi.result_ok) {
        return error.ToolLayoutInitFailed;
    }
    if (oc_tool_slot_write_pattern(ata_probe_tool_slot_id, ata_probe_tool_slot_byte_len, ata_probe_tool_slot_seed) != abi.result_ok) {
        return error.ToolLayoutWriteFailed;
    }
    const primary_slot = oc_tool_layout_slot(ata_probe_tool_slot_id);
    if (primary_slot.start_lba != ata_probe_tool_slot_expected_lba or
        oc_tool_slot_byte(ata_probe_tool_slot_id, 0) != ata_probe_tool_slot_seed or
        oc_tool_slot_byte(ata_probe_tool_slot_id, 1) != ata_probe_tool_slot_seed +% 1 or
        oc_tool_slot_byte(ata_probe_tool_slot_id, 512) != ata_probe_tool_slot_seed or
        storage_backend.readByte(primary_slot.start_lba, 0) != ata_probe_tool_slot_seed)
    {
        return error.ToolLayoutReadbackFailed;
    }

    if (oc_filesystem_init() != abi.result_ok) {
        return error.FilesystemInitFailed;
    }
    if (oc_filesystem_state_ptr().active_backend != abi.storage_backend_ata_pio) {
        return error.FilesystemInitFailed;
    }
    filesystem.createDirPath(ata_probe_filesystem_dir) catch return error.FilesystemDirCreateFailed;
    filesystem.writeFile(ata_probe_filesystem_path, ata_probe_filesystem_payload, status.ticks) catch return error.FilesystemWriteFailed;
    if (!probeFilesystemContent(ata_probe_filesystem_path, ata_probe_filesystem_payload)) {
        return error.FilesystemReadbackFailed;
    }

    if (oc_storage_select_partition(1) != abi.result_ok) {
        return error.PartitionExportMismatch;
    }
    if (oc_storage_logical_base_lba() != ata_probe_secondary_partition_start_lba or
        oc_storage_selected_partition_index() != 1 or
        storage_backend.statePtr().block_count != ata_probe_secondary_partition_sector_count)
    {
        return error.PartitionExportMismatch;
    }
    if (oc_tool_layout_state_ptr().formatted != 0 or
        oc_filesystem_state_ptr().formatted != 0 or
        oc_filesystem_state_ptr().mounted != 0)
    {
        return error.ToolLayoutReloadFailed;
    }

    if (oc_tool_layout_format() != abi.result_ok) {
        return error.ToolLayoutFormatFailed;
    }
    if (oc_tool_slot_write_pattern(ata_probe_tool_slot_id, ata_probe_tool_slot_byte_len, ata_probe_secondary_tool_slot_seed) != abi.result_ok) {
        return error.ToolLayoutWriteFailed;
    }
    const secondary_slot = oc_tool_layout_slot(ata_probe_tool_slot_id);
    if (secondary_slot.start_lba != ata_probe_tool_slot_expected_lba or
        oc_tool_slot_byte(ata_probe_tool_slot_id, 0) != ata_probe_secondary_tool_slot_seed or
        oc_tool_slot_byte(ata_probe_tool_slot_id, 512) != ata_probe_secondary_tool_slot_seed or
        storage_backend.readByte(secondary_slot.start_lba, 0) != ata_probe_secondary_tool_slot_seed)
    {
        return error.ToolLayoutReadbackFailed;
    }

    if (oc_filesystem_format() != abi.result_ok) {
        return error.FilesystemFormatFailed;
    }
    if (oc_filesystem_state_ptr().active_backend != abi.storage_backend_ata_pio) {
        return error.FilesystemFormatFailed;
    }
    filesystem.createDirPath(ata_probe_filesystem_dir) catch return error.FilesystemDirCreateFailed;
    filesystem.writeFile(ata_probe_filesystem_path, ata_probe_secondary_filesystem_payload, status.ticks) catch return error.FilesystemWriteFailed;
    if (!probeFilesystemContent(ata_probe_filesystem_path, ata_probe_secondary_filesystem_payload)) {
        return error.FilesystemReadbackFailed;
    }

    if (oc_storage_select_partition(0) != abi.result_ok) {
        return error.PartitionExportMismatch;
    }
    if (oc_tool_layout_init() != abi.result_ok) {
        return error.ToolLayoutReloadFailed;
    }
    if (oc_tool_slot_byte(ata_probe_tool_slot_id, 0) != ata_probe_tool_slot_seed or
        oc_tool_slot_byte(ata_probe_tool_slot_id, 512) != ata_probe_tool_slot_seed)
    {
        return error.ToolLayoutReloadFailed;
    }

    if (oc_filesystem_init() != abi.result_ok) {
        return error.FilesystemReloadFailed;
    }
    if (oc_filesystem_state_ptr().active_backend != abi.storage_backend_ata_pio or
        !probeFilesystemContent(ata_probe_filesystem_path, ata_probe_filesystem_payload))
    {
        return error.FilesystemReloadFailed;
    }

    if (oc_storage_select_partition(1) != abi.result_ok) {
        return error.PartitionExportMismatch;
    }
    if (oc_tool_layout_init() != abi.result_ok) {
        return error.ToolLayoutReloadFailed;
    }
    if (oc_tool_slot_byte(ata_probe_tool_slot_id, 0) != ata_probe_secondary_tool_slot_seed or
        oc_tool_slot_byte(ata_probe_tool_slot_id, 512) != ata_probe_secondary_tool_slot_seed)
    {
        return error.ToolLayoutReloadFailed;
    }

    if (oc_filesystem_init() != abi.result_ok) {
        return error.FilesystemReloadFailed;
    }
    if (oc_filesystem_state_ptr().active_backend != abi.storage_backend_ata_pio or
        !probeFilesystemContent(ata_probe_filesystem_path, ata_probe_secondary_filesystem_payload))
    {
        return error.FilesystemReloadFailed;
    }

    if (oc_storage_select_partition(0) != abi.result_ok) {
        return error.PartitionExportMismatch;
    }
    if (oc_tool_layout_init() != abi.result_ok) {
        return error.ToolLayoutReloadFailed;
    }
    if (oc_filesystem_init() != abi.result_ok) {
        return error.FilesystemReloadFailed;
    }
}

fn runAtaGptInstallerProbe() AtaGptInstallerProbeError!void {
    storage_backend.init();
    const storage = storage_backend.statePtr();
    if (storage.backend != abi.storage_backend_ata_pio or storage.mounted == 0) {
        return error.AtaBackendUnavailable;
    }
    if (storage.block_count < ata_gpt_probe_raw_lba + 1) {
        return error.PartitionMountMismatch;
    }

    if (oc_storage_write_pattern(ata_gpt_probe_raw_lba, 1, ata_gpt_probe_raw_seed) != abi.result_ok) {
        return error.RawPatternWriteFailed;
    }
    if (oc_storage_flush() != abi.result_ok) {
        return error.RawPatternFlushFailed;
    }
    if (oc_storage_read_byte(ata_gpt_probe_raw_lba, 0) != ata_gpt_probe_raw_seed or
        oc_storage_read_byte(ata_gpt_probe_raw_lba, 1) != ata_gpt_probe_raw_seed +% 1)
    {
        return error.RawPatternReadbackFailed;
    }

    tool_layout.resetForTest();
    filesystem.resetForTest();
    disk_installer.installDefaultLayout(status.ticks) catch return error.InstallerFailed;
    if (tool_layout.statePtr().formatted == 0 or filesystem.statePtr().active_backend != abi.storage_backend_ata_pio) {
        return error.InstallerFailed;
    }

    var loader_buf: [160]u8 = undefined;
    const expected_loader = disk_installer.loaderConfigForCurrentBackend(loader_buf[0..]) catch return error.LoaderCfgReadbackFailed;
    if (!probeFilesystemContent(disk_installer.loader_cfg_path, expected_loader)) {
        return error.LoaderCfgReadbackFailed;
    }

    var kernel_buf: [128]u8 = undefined;
    const expected_kernel = disk_installer.kernelConfigForCurrentBackend(kernel_buf[0..]) catch return error.KernelInfoReadbackFailed;
    if (!probeFilesystemContent(disk_installer.kernel_info_path, expected_kernel)) {
        return error.KernelInfoReadbackFailed;
    }

    var manifest_buf: [192]u8 = undefined;
    const expected_manifest = disk_installer.installManifestForCurrentBackend(manifest_buf[0..]) catch return error.ManifestReadbackFailed;
    if (!probeFilesystemContent(disk_installer.install_manifest_path, expected_manifest)) {
        return error.ManifestReadbackFailed;
    }

    var package_scratch: [256]u8 = undefined;
    if (storage.backend != abi.storage_backend_virtio_block or storage.mounted == 0) {
        return error.BackendUnavailable;
    }
    if (storage.block_size != 512) return error.StateMismatch;
    if (storage.block_count < virtio_block_probe_raw_lba + virtio_block_probe_block_count) {
    if (storage.backend != abi.storage_backend_virtio_block or storage.mounted == 0) {
        return error.BackendUnavailable;
    }
    if (storage.block_count < 256) {
fn runVirtioBlockMountProbe() VirtioBlockMountProbeError!void {
    var probe_allocator_backing = [_]u8{0} ** 8192;
    if (storage.backend != abi.storage_backend_virtio_block or storage.mounted == 0) {
        return error.BackendUnavailable;
    }
    if (storage.block_count < 256) {
    if (oc_filesystem_bind_mount("boot".ptr, 4, "/boot".ptr, 5, status.ticks + 1) != abi.result_ok) return error.BootMountBindFailed;
    if (oc_filesystem_bind_mount("runtime".ptr, 7, "/runtime".ptr, 8, status.ticks + 2) != abi.result_ok) return error.RuntimeMountBindFailed;
    if (oc_filesystem_bind_mount("cache".ptr, 5, "/tmp/cache".ptr, 10, status.ticks + 3) != abi.result_ok) return error.CacheMountBindFailed;
    if (oc_filesystem_mount_count() != 3) return error.MountExportMismatch;

    const boot_mount = oc_filesystem_mount_entry(0);
    const runtime_mount = oc_filesystem_mount_entry(1);
    const cache_mount = oc_filesystem_mount_entry(2);
    if (!std.mem.eql(u8, boot_mount.name[0..boot_mount.name_len], "boot") or
        !std.mem.eql(u8, runtime_mount.name[0..runtime_mount.name_len], "runtime") or
        !std.mem.eql(u8, cache_mount.name[0..cache_mount.name_len], "cache") or
        !std.mem.eql(u8, boot_mount.target[0..boot_mount.target_len], "/boot") or
        !std.mem.eql(u8, runtime_mount.target[0..runtime_mount.target_len], "/runtime") or
        !std.mem.eql(u8, cache_mount.target[0..cache_mount.target_len], "/tmp/cache"))
    {
        return error.MountExportMismatch;
    }

    if (oc_filesystem_remove_mount("boot".ptr, 4, status.ticks + 4) != abi.result_ok) return error.BootMountRemoveFailed;
    if (oc_filesystem_mount_count() != 2) return error.MountExportMismatch;
    if (oc_filesystem_bind_mount("boot".ptr, 4, "/boot".ptr, 5, status.ticks + 5) != abi.result_ok) return error.BootMountBindFailed;
    if (oc_filesystem_mount_count() != 3) return error.MountExportMismatch;

    var target_buf: [filesystem.max_path_len]u8 = undefined;
    const boot_target = filesystem.mountTarget("boot", target_buf[0..]) orelse return error.BootAliasTargetMismatch;
    if (!std.mem.eql(u8, boot_target, "/boot")) return error.BootAliasTargetMismatch;
    const runtime_target = filesystem.mountTarget("runtime", target_buf[0..]) orelse return error.RuntimeAliasTargetMismatch;
    if (!std.mem.eql(u8, runtime_target, "/runtime")) return error.RuntimeAliasTargetMismatch;
    const cache_target = filesystem.mountTarget("cache", target_buf[0..]) orelse return error.CacheAliasTargetMismatch;
    if (!std.mem.eql(u8, cache_target, "/tmp/cache")) return error.CacheAliasTargetMismatch;

    const root_listing = filesystem.listDirectoryAlloc(probe_allocator, "/", 256) catch return error.RootVfsListingMismatch;
    defer probe_allocator.free(root_listing);
    if (std.mem.indexOf(u8, root_listing, "dir mnt\n") == null or
        std.mem.indexOf(u8, root_listing, "dir tmp\n") == null or
        std.mem.indexOf(u8, root_listing, "dir proc\n") == null or
        std.mem.indexOf(u8, root_listing, "dir dev\n") == null or
        std.mem.indexOf(u8, root_listing, "dir sys\n") == null)
    {
        return error.RootVfsListingMismatch;
    }

    var loader_buf: [160]u8 = undefined;
    const expected_loader = disk_installer.loaderConfigForCurrentBackend(loader_buf[0..]) catch return error.LoaderAliasReadbackFailed;
    if (!probeFilesystemContent("/mnt/boot/loader.cfg", expected_loader)) {
        return error.LoaderAliasReadbackFailed;
    }

    const proc_version = filesystem.readFileAlloc(probe_allocator, "/proc/version", 256) catch return error.ProcVersionReadbackFailed;
    defer probe_allocator.free(proc_version);
    if (std.mem.indexOf(u8, proc_version, "project=ZAR-Zig-Agent-Runtime") == null) return error.ProcVersionReadbackFailed;

    const storage_state = filesystem.readFileAlloc(probe_allocator, "/sys/storage/state", 256) catch return error.StorageStateReadFailed;
    defer probe_allocator.free(storage_state);
    if (std.mem.indexOf(u8, storage_state, "backend=virtio_block") == null) return error.StorageStateBackendMismatch;
    if (std.mem.indexOf(u8, storage_state, "detected_filesystem=zarfs") == null) return error.StorageStateFilesystemMismatch;

    const storage_backends = filesystem.readFileAlloc(probe_allocator, "/sys/storage/backends", 1024) catch return error.StorageBackendRegistryReadbackFailed;
    defer probe_allocator.free(storage_backends);
    if (std.mem.indexOf(u8, storage_backends, "backend[0]=name=ram_disk backend=ram_disk available=1 selected=0 mounted=1") == null or
        std.mem.indexOf(u8, storage_backends, "backend[1]=name=ata_pio backend=ata_pio available=0 selected=0 mounted=0") == null or
        std.mem.indexOf(u8, storage_backends, "backend[2]=name=virtio_block backend=virtio_block available=1 selected=1 mounted=1 preferred_order=2 filesystem=zarfs") == null)
    {
        return error.StorageBackendRegistryReadbackFailed;
    }

    const storage_filesystems = filesystem.readFileAlloc(probe_allocator, "/sys/storage/filesystems", 512) catch return error.StorageFilesystemMatrixReadbackFailed;
    defer probe_allocator.free(storage_filesystems);
    if (std.mem.indexOf(u8, storage_filesystems, "filesystem=zarfs detect=1 mount=1 write=1 source=zar_native") == null or
        std.mem.indexOf(u8, storage_filesystems, "filesystem=ext2 detect=1 mount=1 write=0 source=zar_bounded_read_only") == null or
        std.mem.indexOf(u8, storage_filesystems, "filesystem=fat32 detect=1 mount=1 write=1 source=zar_bounded_writable_one_level_83") == null)
    {
        return error.StorageFilesystemMatrixReadbackFailed;
    }

    const storage_registry_text = filesystem.readFileAlloc(probe_allocator, "/sys/storage/registry", 2048) catch return error.StorageRegistryReadbackFailed;
    defer probe_allocator.free(storage_registry_text);
    if (std.mem.indexOf(u8, storage_registry_text, "name=root path=/ target=/ layer=persistent backend=virtio_block filesystem=zarfs") == null or
        std.mem.indexOf(u8, storage_registry_text, "name=boot path=/mnt/boot target=/boot layer=persistent backend=virtio_block filesystem=zarfs") == null or
        std.mem.indexOf(u8, storage_registry_text, "name=runtime path=/mnt/runtime target=/runtime layer=persistent backend=virtio_block filesystem=zarfs") == null or
        std.mem.indexOf(u8, storage_registry_text, "name=cache path=/mnt/cache target=/tmp/cache layer=tmpfs backend=none filesystem=tmpfs") == null)
    {
        return error.StorageRegistryReadbackFailed;
    }

    filesystem.createDirPath("/mnt/runtime/state") catch return error.RuntimeAliasWriteFailed;
    filesystem.writeFile("/mnt/runtime/state/mounted-via-alias.txt", "mounted-via-alias", status.ticks + 6) catch return error.RuntimeAliasWriteFailed;
    filesystem.createDirPath("/mnt/cache") catch return error.CacheAliasWriteFailed;
    filesystem.writeFile("/mnt/cache/volatile.txt", "volatile-cache", status.ticks + 7) catch return error.CacheAliasWriteFailed;
    if (!probeFilesystemContent("/mnt/cache/volatile.txt", "volatile-cache")) return error.CacheAliasWriteFailed;

    filesystem.resetForTest();
    tool_layout.resetForTest();
    filesystem.init() catch return error.RuntimeAliasReloadFailed;

    const reloaded_target = filesystem.mountTarget("runtime", target_buf[0..]) orelse return error.RuntimeAliasReloadFailed;
    if (!std.mem.eql(u8, reloaded_target, "/runtime") or
        !probeFilesystemContent("/mnt/runtime/state/mounted-via-alias.txt", "mounted-via-alias"))
    {
        return error.RuntimeAliasReloadFailed;
    }
    const reloaded_cache_target = filesystem.mountTarget("cache", target_buf[0..]) orelse return error.TmpfsAliasVolatilityMismatch;
    if (!std.mem.eql(u8, reloaded_cache_target, "/tmp/cache")) return error.TmpfsAliasVolatilityMismatch;
    if (probeFilesystemContent("/mnt/cache/volatile.txt", "volatile-cache")) return error.TmpfsAliasVolatilityMismatch;
    var cache_buf: [64]u8 = undefined;
    const cache_read = filesystem.readFile("/mnt/cache/volatile.txt", cache_buf[0..]);
    if (cache_read != error.FileNotFound) return error.TmpfsAliasVolatilityMismatch;

    if (builtin.is_test) {
        return;
    }

    const device = pci.discoverVirtioBlockDevice() orelse return error.PciDiscoveryMismatch;
    if (device.vendor_id != 0x1AF4 or device.device_id != 0x1042) {
        return error.PciDiscoveryMismatch;
    }
}

fn runVirtioBlockMountControlProbe() VirtioBlockMountControlProbeError!void {
    var probe_allocator_backing = [_]u8{0} ** 4096;
    if (storage.backend != abi.storage_backend_virtio_block or storage.mounted == 0) return error.BackendUnavailable;
        std.mem.indexOf(u8, storage_backends_result.stdout, "backend[2]=name=virtio_block backend=virtio_block available=1 selected=1 mounted=1") == null)
    {
        return error.StorageBackendsReadFailed;
    }

        std.mem.indexOf(u8, storage_filesystems_result.stdout, "filesystem=fat32 detect=1 mount=1 write=1 source=zar_bounded_writable_one_level_83") == null)
    {
        return error.StorageFilesystemsReadFailed;
    }

    const backend_info_response = tool_service.handleFramedRequest(
        probe_allocator,
        "REQ 41 STORAGEBACKENDINFO virtio_block",
        1024,
        256,
        1024,
    ) catch return error.StorageBackendInfoReadFailed;
    defer probe_allocator.free(backend_info_response);
    if (!std.mem.startsWith(u8, backend_info_response, "RESP 41 ") or
        std.mem.indexOf(u8, backend_info_response, "backend[2]=name=virtio_block backend=virtio_block available=1 selected=1 mounted=1") == null)
    {
        return error.StorageBackendInfoReadFailed;
    }

    const mount_bind_response = tool_service.handleFramedRequest(
        probe_allocator,
        "REQ 42 MOUNTBIND state /runtime/state",
        1024,
        256,
        512,
    ) catch return error.MountBindFailed;
    defer probe_allocator.free(mount_bind_response);
    if (!std.mem.eql(u8, mount_bind_response, "RESP 42 31\nMOUNTBIND state /runtime/state\n")) return error.MountBindFailed;

    if (oc_filesystem_mount_count() != 1) return error.MountExportMismatch;

    const mount = oc_filesystem_mount_entry(0);
    if (!std.mem.eql(u8, mount.name[0..mount.name_len], "state") or
        !std.mem.eql(u8, mount.target[0..mount.target_len], "/runtime/state") or
        mount.modified_tick != 0)
    {
        return error.MountExportMismatch;
    }

    const mount_list_response = tool_service.handleFramedRequest(
        probe_allocator,
        "REQ 43 MOUNTLIST",
        1024,
        256,
        512,
    ) catch return error.MountListReadFailed;
    defer probe_allocator.free(mount_list_response);
    if (!std.mem.eql(u8, mount_list_response, "RESP 43 71\nmount name=state path=/mnt/state target=/runtime/state modified_tick=0\n")) {
        return error.MountListReadFailed;
    }

    defer mount_info_result.deinit(probe_allocator);
    if (mount_info_result.exit_code != 0 or
        !std.mem.eql(u8, mount_info_result.stdout, "mount name=state path=/mnt/state target=/runtime/state modified_tick=0\n"))
    {
        return error.MountInfoReadFailed;
    }

    filesystem.createDirPath("/mnt/state") catch return error.AliasWriteFailed;
    filesystem.writeFile("/mnt/state/control.txt", "virtio-block-mount-control", status.ticks + 2) catch return error.AliasWriteFailed;
    if (!probeFilesystemContent("/mnt/state/control.txt", "virtio-block-mount-control")) return error.AliasReadbackFailed;

    filesystem.resetForTest();
    storage_backend.init();
    filesystem.init() catch return error.ReloadFailed;
    if (oc_filesystem_mount_count() != 1) return error.ReloadFailed;
    const reload_mount = oc_filesystem_mount_entry(0);
    if (!std.mem.eql(u8, reload_mount.name[0..reload_mount.name_len], "state") or
        !std.mem.eql(u8, reload_mount.target[0..reload_mount.target_len], "/runtime/state"))
    {
        return error.ReloadFailed;
    }
    if (!probeFilesystemContent("/mnt/state/control.txt", "virtio-block-mount-control")) return error.ReloadFailed;

    const mount_remove_response = tool_service.handleFramedRequest(
        probe_allocator,
        "REQ 44 MOUNTREMOVE state",
        1024,
        256,
        512,
    ) catch return error.MountRemoveFailed;
    defer probe_allocator.free(mount_remove_response);
    if (!std.mem.eql(u8, mount_remove_response, "RESP 44 18\nMOUNTREMOVE state\n")) return error.MountRemoveFailed;
    if (oc_filesystem_mount_count() != 0) return error.MountRemoveFailed;
    const registry_read = filesystem.readFileAlloc(probe_allocator, "/runtime/mounts/state.txt", 64) catch |err| switch (err) {
        error.FileNotFound => null,
        else => return error.MountRemoveFailed,
    };
    if (registry_read) |payload| {
        probe_allocator.free(payload);
        return error.MountRemoveFailed;
    }

    if (builtin.is_test) return;
    const device = pci.discoverVirtioBlockDevice() orelse return error.PciDiscoveryMismatch;
    if (device.vendor_id != 0x1AF4 or device.device_id != 0x1042) return error.PciDiscoveryMismatch;
}

fn runVirtioBlockExt2MountProbe() VirtioBlockExt2MountProbeError!void {
    runVirtioBlockExternalFsProbe(
        VirtioBlockExt2MountProbeError,
        .ext2,
        ext2_ro.test_file_name,
        ext2_ro.test_file_payload,
        ext2_ro.seedTestImage,
    ) catch |err| return err;
}

fn runVirtioBlockFat32MountProbe() VirtioBlockFat32MountProbeError!void {
    runVirtioBlockExternalFsProbe(
        VirtioBlockFat32MountProbeError,
        .fat32,
        fat32_ro.test_file_name,
        fat32_ro.test_file_payload,
        fat32_ro.seedTestImage,
    ) catch |err| return err;
}

fn runVirtioBlockExternalFsProbe(
    comptime ProbeError: type,
    comptime filesystem_kind: storage_registry.FilesystemKind,
    comptime file_name: []const u8,
    expected_payload: []const u8,
    seed_fn: fn () anyerror!void,
) ProbeError!void {
    var probe_allocator_backing = [_]u8{0} ** 8192;
    if (storage.backend != abi.storage_backend_virtio_block or storage.mounted == 0) return error.BackendUnavailable;
    if (oc_filesystem_bind_mount("external".ptr, 8, mounted_external_fs.active_root.ptr, mounted_external_fs.active_root.len, status.ticks + 1) != abi.result_ok) {
        return error.ExternalAliasBindFailed;
    }
    if (oc_filesystem_mount_count() != 1) return error.ExternalAliasMountExportMismatch;
    const external_mount = oc_filesystem_mount_entry(0);
    if (!std.mem.eql(u8, external_mount.name[0..external_mount.name_len], "external") or
        !std.mem.eql(u8, external_mount.target[0..external_mount.target_len], mounted_external_fs.active_root))
    {
        return error.ExternalAliasMountExportMismatch;
    }

    const listing = filesystem.listDirectoryAlloc(probe_allocator, "/mnt/external", 256) catch return error.ExternalAliasListingFailed;
    defer probe_allocator.free(listing);
    const expected_listing = switch (filesystem_kind) {
        .ext2 => std.fmt.allocPrint(probe_allocator, "file {s} {d}\n", .{ file_name, expected_payload.len }) catch return error.ExternalAliasListingFailed,
        .fat32 => std.fmt.allocPrint(
            probe_allocator,
            "file {s} {d}\ndir {s}\n",
            .{ file_name, expected_payload.len, fat32_ro.test_subdir_name },
        ) catch return error.ExternalAliasListingFailed,
        else => return error.ExternalAliasListingFailed,
    };
    defer probe_allocator.free(expected_listing);
    if (!std.mem.eql(u8, listing, expected_listing)) return error.ExternalAliasListingFailed;

    var mounted_path_buf: [96]u8 = undefined;
    const mounted_path = std.fmt.bufPrint(mounted_path_buf[0..], "/mnt/external/{s}", .{file_name}) catch return error.ExternalAliasReadbackFailed;
    const payload = filesystem.readFileAlloc(probe_allocator, mounted_path, 128) catch return error.ExternalAliasReadbackFailed;
    defer probe_allocator.free(payload);
    if (!std.mem.eql(u8, payload, expected_payload)) return error.ExternalAliasReadbackFailed;

    const stat = filesystem.statSummary(mounted_path) catch return error.ExternalAliasStatFailed;
    if (stat.kind != .file or stat.size != expected_payload.len) return error.ExternalAliasStatFailed;

    switch (filesystem_kind) {
        .ext2 => {
            if (filesystem.writeFile("/mnt/external/FAIL.TXT", "x", status.ticks + 2)) {
                return error.ReadOnlyWriteMismatch;
            } else |err| {
                if (err != error.ReadOnlyPath) return error.ReadOnlyWriteMismatch;
            }
        },
        .fat32 => {
            filesystem.writeFile("/mnt/external/WRITE.TXT", "fat32-mounted-write", status.ticks + 2) catch return error.ExternalAliasWriteFailed;
            if (!probeFilesystemContent("/mnt/external/WRITE.TXT", "fat32-mounted-write")) return error.ExternalAliasWriteFailed;

            filesystem.writeFile("/mnt/external/WRITE.TXT", "fat32-overwrite", status.ticks + 3) catch return error.ExternalAliasOverwriteFailed;
            if (!probeFilesystemContent("/mnt/external/WRITE.TXT", "fat32-overwrite")) return error.ExternalAliasOverwriteFailed;

            filesystem.deleteFile("/mnt/external/WRITE.TXT", status.ticks + 4) catch return error.ExternalAliasDeleteFailed;
            const deleted = filesystem.readFileAlloc(probe_allocator, "/mnt/external/WRITE.TXT", 64);
            if (deleted != error.FileNotFound) return error.ExternalAliasDeleteFailed;

            const nested_listing = filesystem.listDirectoryAlloc(probe_allocator, "/mnt/external/DATA", 256) catch return error.NestedAliasListingFailed;
            defer probe_allocator.free(nested_listing);
            if (std.mem.indexOf(u8, nested_listing, "file NOTE.TXT 23\n") == null) return error.NestedAliasListingFailed;

            const nested_payload = filesystem.readFileAlloc(probe_allocator, "/mnt/external/DATA/NOTE.TXT", 64) catch return error.NestedAliasReadbackFailed;
            defer probe_allocator.free(nested_payload);
            if (!std.mem.eql(u8, nested_payload, fat32_ro.test_nested_file_payload)) return error.NestedAliasReadbackFailed;

            filesystem.writeFile("/mnt/external/DATA/WRITE.TXT", "fat32-nested-write", status.ticks + 5) catch return error.NestedAliasWriteFailed;
            if (!probeFilesystemContent("/mnt/external/DATA/WRITE.TXT", "fat32-nested-write")) return error.NestedAliasWriteFailed;

            filesystem.writeFile("/mnt/external/DATA/WRITE.TXT", "fat32-nested-overwrite", status.ticks + 6) catch return error.NestedAliasOverwriteFailed;
            if (!probeFilesystemContent("/mnt/external/DATA/WRITE.TXT", "fat32-nested-overwrite")) return error.NestedAliasOverwriteFailed;

            filesystem.deleteFile("/mnt/external/DATA/WRITE.TXT", status.ticks + 7) catch return error.NestedAliasDeleteFailed;
            const nested_deleted = filesystem.readFileAlloc(probe_allocator, "/mnt/external/DATA/WRITE.TXT", 64);
            if (nested_deleted != error.FileNotFound) return error.NestedAliasDeleteFailed;

            filesystem.createDirPath("/mnt/external/CACHE") catch return error.DirectoryAliasCreateFailed;
            const root_listing_after_dir = filesystem.listDirectoryAlloc(probe_allocator, "/mnt/external", 256) catch return error.DirectoryAliasReadbackFailed;
            defer probe_allocator.free(root_listing_after_dir);
            if (std.mem.indexOf(u8, root_listing_after_dir, "dir CACHE\n") == null) return error.DirectoryAliasReadbackFailed;

            filesystem.writeFile("/mnt/external/CACHE/LOG.TXT", "fat32-dir-write", status.ticks + 8) catch return error.DirectoryAliasWriteFailed;
            if (!probeFilesystemContent("/mnt/external/CACHE/LOG.TXT", "fat32-dir-write")) return error.DirectoryAliasWriteFailed;

            filesystem.createDirPath("/mnt/external/DATA/ARCHIVE") catch return error.NestedDirectoryAliasCreateFailed;
            const nested_listing_after_dir = filesystem.listDirectoryAlloc(probe_allocator, "/mnt/external/DATA", 256) catch return error.NestedDirectoryAliasCreateFailed;
            defer probe_allocator.free(nested_listing_after_dir);
            if (std.mem.indexOf(u8, nested_listing_after_dir, "dir ARCHIVE\n") == null) return error.NestedDirectoryAliasCreateFailed;

            filesystem.deleteTree("/mnt/external/CACHE", status.ticks + 9) catch return error.DirectoryAliasDeleteFailed;
            if (filesystem.readFileAlloc(probe_allocator, "/mnt/external/CACHE/LOG.TXT", 64) != error.FileNotFound) return error.DirectoryAliasDeleteFailed;
            const root_listing_after_delete = filesystem.listDirectoryAlloc(probe_allocator, "/mnt/external", 256) catch return error.DirectoryAliasDeleteFailed;
            defer probe_allocator.free(root_listing_after_delete);
            if (std.mem.indexOf(u8, root_listing_after_delete, "dir CACHE\n") != null) return error.DirectoryAliasDeleteFailed;

            filesystem.deleteTree("/mnt/external/DATA/ARCHIVE", status.ticks + 10) catch return error.NestedDirectoryAliasDeleteFailed;
            const nested_listing_after_delete = filesystem.listDirectoryAlloc(probe_allocator, "/mnt/external/DATA", 256) catch return error.NestedDirectoryAliasDeleteFailed;
            defer probe_allocator.free(nested_listing_after_delete);
            if (std.mem.indexOf(u8, nested_listing_after_delete, "dir ARCHIVE\n") != null) return error.NestedDirectoryAliasDeleteFailed;
        },
        else => {},
    }

    const storage_filesystems = filesystem.readFileAlloc(probe_allocator, "/sys/storage/filesystems", 512) catch return error.FilesystemMatrixReadbackFailed;
    defer probe_allocator.free(storage_filesystems);
    const expected_filesystem_row = switch (filesystem_kind) {
        .ext2 => "filesystem=ext2 detect=1 mount=1 write=0 source=zar_bounded_read_only",
        .fat32 => "filesystem=fat32 detect=1 mount=1 write=1 source=zar_bounded_writable_one_level_83",
        else => return error.FilesystemMatrixReadbackFailed,
    };
    if (std.mem.indexOf(u8, storage_filesystems, expected_filesystem_row) == null) return error.FilesystemMatrixReadbackFailed;

    const storage_registry_text = filesystem.readFileAlloc(probe_allocator, "/sys/storage/registry", 2048) catch return error.StorageRegistryReadbackFailed;
    defer probe_allocator.free(storage_registry_text);
    const expected_registry_row = switch (filesystem_kind) {
        .ext2 => "name=external path=/mnt/external target=/__storagefs/active layer=persistent backend=virtio_block filesystem=ext2",
        .fat32 => "name=external path=/mnt/external target=/__storagefs/active layer=persistent backend=virtio_block filesystem=fat32",
        else => return error.StorageRegistryReadbackFailed,
    };
    if (std.mem.indexOf(u8, storage_registry_text, expected_registry_row) == null) return error.StorageRegistryReadbackFailed;

    const storage_backends = filesystem.readFileAlloc(probe_allocator, "/sys/storage/backends", 1024) catch return error.BackendRegistryReadbackFailed;
    defer probe_allocator.free(storage_backends);
    if (std.mem.indexOf(u8, storage_backends, "backend[0]=name=ram_disk backend=ram_disk available=1 selected=0 mounted=1") == null or
        std.mem.indexOf(u8, storage_backends, "backend[2]=name=virtio_block backend=virtio_block available=1 selected=1 mounted=1") == null)
    {
        return error.BackendRegistryReadbackFailed;
    }

    if (!builtin.is_test) {
        const device = pci.discoverVirtioBlockDevice() orelse return error.PciDiscoveryMismatch;
        if (device.vendor_id != 0x1AF4 or device.device_id != 0x1042) return error.PciDiscoveryMismatch;
    }
}

        "REQ 178 CMD mount-bind cache /tmp/sh/CACHE\\ DIR",
        256,
        256,
        256,
    );
    if (!std.mem.startsWith(u8, direct_mount_bind_response, "RESP 178 ")) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, direct_mount_bind_response, "mount bound cache -> /tmp/sh/CACHE DIR\n") == null) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9AF1\n");

    if (!std.mem.eql(u8, direct_mount_readback, "RESP 179 10\ncache-item")) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9AF2\n");

        error.PartitionMountMismatch => 0x43,
        error.RawPatternWriteFailed => 0x44,
        error.RawPatternFlushFailed => 0x45,
        error.RawPatternReadbackFailed => 0x46,
        error.PartitionExportMismatch => 0x47,
        error.SecondaryRawPatternWriteFailed => 0x48,
        error.SecondaryRawPatternReadbackFailed => 0x49,
        error.ToolLayoutInitFailed => 0x4A,
        error.ToolLayoutFormatFailed => 0x4B,
        error.ToolLayoutWriteFailed => 0x4C,
        error.ToolLayoutReadbackFailed => 0x4D,
        error.ToolLayoutReloadFailed => 0x4E,
        error.FilesystemInitFailed => 0x4F,
        error.FilesystemFormatFailed => 0x50,
        error.FilesystemDirCreateFailed => 0x51,
        error.FilesystemWriteFailed => 0x52,
        error.FilesystemReadbackFailed => 0x53,
        error.FilesystemReloadFailed => 0x54,
    };
}

fn ataGptInstallerProbeFailureCode(err: AtaGptInstallerProbeError) u8 {
    return switch (err) {
        error.AtaBackendUnavailable => 0x50,
        error.PartitionMountMismatch => 0x52,
        error.RawPatternWriteFailed => 0x53,
        error.RawPatternFlushFailed => 0x54,
        error.RawPatternReadbackFailed => 0x55,
        error.InstallerFailed => 0x56,
        error.LoaderCfgReadbackFailed => 0x57,
        error.KernelInfoReadbackFailed => 0x58,
        error.ManifestReadbackFailed => 0x59,
        error.PackageListFailed => 0x5A,
fn virtioBlockMountProbeFailureCode(err: VirtioBlockMountProbeError) u8 {
    return switch (err) {
        error.BackendUnavailable => 0x7D,
        error.BootMountBindFailed => 0x81,
        error.RuntimeMountBindFailed => 0x82,
        error.CacheMountBindFailed => 0x83,
        error.BootMountRemoveFailed => 0x84,
        error.MountExportMismatch => 0x85,
        error.BootAliasTargetMismatch => 0x86,
        error.RuntimeAliasTargetMismatch => 0x87,
        error.CacheAliasTargetMismatch => 0x88,
        error.LoaderAliasReadbackFailed => 0x89,
        error.RuntimeAliasWriteFailed => 0x8A,
        error.CacheAliasWriteFailed => 0x8B,
        error.RootVfsListingMismatch => 0x8C,
        error.ProcVersionReadbackFailed => 0x8D,
        error.StorageStateReadFailed => 0x8E,
        error.StorageStateBackendMismatch => 0x8F,
        error.StorageStateFilesystemMismatch => 0x90,
        error.StorageBackendRegistryReadbackFailed => 0x91,
        error.StorageFilesystemMatrixReadbackFailed => 0x92,
        error.StorageRegistryReadbackFailed => 0x93,
        error.RuntimeAliasReloadFailed => 0x94,
        error.TmpfsAliasVolatilityMismatch => 0x95,
        error.PciDiscoveryMismatch => 0x96,
    };
}

fn virtioBlockExt2MountProbeFailureCode(err: VirtioBlockExt2MountProbeError) u8 {
    return switch (err) {
        error.BackendUnavailable => 0x94,
        error.ExternalAliasMountExportMismatch => 0x9A,
        error.ExternalAliasListingFailed => 0x9B,
        error.ExternalAliasReadbackFailed => 0x9C,
        error.ExternalAliasStatFailed => 0x9D,
        error.ReadOnlyWriteMismatch => 0x9E,
        error.FilesystemMatrixReadbackFailed => 0x9F,
        error.StorageRegistryReadbackFailed => 0xA0,
        error.BackendRegistryReadbackFailed => 0xA1,
        error.PciDiscoveryMismatch => 0xA2,
    };
}

fn virtioBlockFat32MountProbeFailureCode(err: VirtioBlockFat32MountProbeError) u8 {
    return switch (err) {
        error.BackendUnavailable => 0xA2,
        error.ExternalAliasMountExportMismatch => 0xA8,
        error.ExternalAliasListingFailed => 0xA9,
        error.ExternalAliasReadbackFailed => 0xAA,
        error.ExternalAliasStatFailed => 0xAB,
        error.ExternalAliasWriteFailed => 0xAC,
        error.ExternalAliasOverwriteFailed => 0xAD,
        error.ExternalAliasDeleteFailed => 0xAE,
        error.NestedAliasListingFailed => 0xAF,
        error.NestedAliasReadbackFailed => 0xB0,
        error.NestedAliasWriteFailed => 0xB1,
        error.NestedAliasOverwriteFailed => 0xB2,
        error.NestedAliasDeleteFailed => 0xB3,
        error.DirectoryAliasCreateFailed => 0xB4,
        error.DirectoryAliasReadbackFailed => 0xB5,
        error.DirectoryAliasWriteFailed => 0xB6,
        error.DirectoryAliasDeleteFailed => 0xB7,
        error.NestedDirectoryAliasCreateFailed => 0xB8,
        error.NestedDirectoryAliasDeleteFailed => 0xB9,
        error.FilesystemMatrixReadbackFailed => 0xBA,
        error.StorageRegistryReadbackFailed => 0xBB,
        error.BackendRegistryReadbackFailed => 0xBC,
        error.PciDiscoveryMismatch => 0xBD,
    };
}

fn virtioBlockMountControlProbeFailureCode(err: VirtioBlockMountControlProbeError) u8 {
    return switch (err) {
        error.BackendUnavailable => 0xC0,
        error.MountBindFailed => 0xC7,
        error.MountExportMismatch => 0xC8,
        error.MountListReadFailed => 0xC9,
        error.MountInfoReadFailed => 0xCA,
        error.AliasWriteFailed => 0xCB,
        error.AliasReadbackFailed => 0xCC,
        error.ReloadFailed => 0xCD,
        error.MountRemoveFailed => 0xCE,
        error.PciDiscoveryMismatch => 0xCF,
    };
}

        error.NotMounted => abi.result_conflict,
        error.NoDevice, error.DeviceFault, error.BusyTimeout, error.ProtocolError => abi.result_not_supported,
        else => abi.result_not_supported,
    };
}

fn copyInputBytes(ptr: [*]const u8, len: u32, out: []u8) ?[]const u8 {
    if (len == 0 or len > out.len) return null;
    const slice = ptr[0..len];
    @memcpy(out[0..slice.len], slice);
    return out[0..slice.len];
}

fn backendInfoFromRegistryEntry(entry: storage_backend_registry.Entry) BaremetalStorageBackendInfo {
    var info = std.mem.zeroes(BaremetalStorageBackendInfo);
    info.backend = entry.backend;
    info.available = entry.available;
    info.selected = entry.selected;
    info.mounted = entry.mounted;
    info.filesystem_kind = @intFromEnum(entry.filesystem_kind);
    info.preferred_order = entry.preferred_order;
    info.partition_count = entry.partition_count;
    info.selected_partition = if (entry.selected_partition == std.math.maxInt(u8))
        -1
    else
        @as(i16, entry.selected_partition);
    info.block_size = entry.block_size;
    info.block_count = entry.block_count;
    info.logical_base_lba = entry.logical_base_lba;
    info.name_len = entry.name_len;
    @memcpy(info.name[0..entry.name_len], entry.nameSlice());
    return info;
}

fn mountInfoFromEntry(entry: mount_table.Entry) BaremetalMountInfo {
    var info = std.mem.zeroes(BaremetalMountInfo);
    info.name_len = entry.name_len;
    info.target_len = entry.target_len;
    info.modified_tick = entry.modified_tick;
    @memcpy(info.name[0..entry.name_len], entry.name[0..entry.name_len]);
    @memcpy(info.target[0..entry.target_len], entry.target[0..entry.target_len]);
    return info;
}

fn recordCommand(seq: u32, opcode: u16, arg0: u64, arg1: u64, result: i16, tick: u64) void {
    try std.testing.expectEqual(@as(u8, 1), storage.mounted);
    try std.testing.expectEqual(@as(u32, storage_backend.block_size), storage.block_size);
    try std.testing.expectEqual(@as(u32, storage_backend.block_count), storage.block_count);
    try std.testing.expectEqual(@as(u32, 0), oc_storage_logical_base_lba());
    try std.testing.expectEqual(@as(u32, 0), oc_storage_partition_count());
    try std.testing.expectEqual(@as(i16, -1), oc_storage_selected_partition_index());
    try std.testing.expectEqual(std.mem.zeroes(BaremetalStoragePartitionInfo), oc_storage_partition_info(0));

    try std.testing.expectEqual(@as(i16, abi.result_ok), oc_storage_write_pattern(4, 2, 0x41));
    try std.testing.expectEqual(@as(u32, 2), storage.write_ops);
    try std.testing.expectEqual(@as(u8, 1), storage.dirty);
    try std.testing.expectEqual(@as(u8, 0x41), oc_storage_read_byte(4, 0));
    try std.testing.expectEqual(@as(u8, 0x42), oc_storage_read_byte(4, 1));
    try std.testing.expectEqual(@as(u8, 0x41), oc_storage_read_byte(5, 0));

    try std.testing.expectEqual(@as(i16, abi.result_ok), oc_storage_flush());
    try std.testing.expectEqual(@as(u32, 1), storage.flush_ops);
    try std.testing.expectEqual(@as(u8, 0), storage.dirty);
}

test "baremetal storage backend facade reports ram-disk backend baseline" {
    resetBaremetalRuntimeForTest();

    oc_storage_init();
    const storage = oc_storage_state_ptr();
    try std.testing.expectEqual(@as(u8, abi.storage_backend_ram_disk), storage.backend);
    try std.testing.expectEqual(@as(u32, storage_backend.block_size), storage.block_size);
    try std.testing.expectEqual(@as(u32, storage_backend.block_count), storage.block_count);
    try std.testing.expectEqual(@as(u8, abi.storage_backend_ram_disk), storage_backend.activeBackend());
}

test "baremetal storage exports report ata pio backend when a device is available" {
    resetBaremetalRuntimeForTest();
    ata_pio_disk.testEnableMockDevice(8192);
    ata_pio_disk.testInstallMockMbrPartition(ata_probe_partition_start_lba, ata_probe_partition_sector_count, 0x83);
    defer ata_pio_disk.testDisableMockDevice();

    oc_storage_init();
    const storage = oc_storage_state_ptr();
    try std.testing.expectEqual(@as(u8, abi.storage_backend_ata_pio), storage.backend);
    try std.testing.expectEqual(@as(u8, 1), storage.mounted);
    try std.testing.expectEqual(@as(u32, ata_probe_partition_sector_count), storage.block_count);
    try std.testing.expectEqual(ata_probe_partition_start_lba, oc_storage_logical_base_lba());
    try std.testing.expectEqual(@as(u32, 1), oc_storage_partition_count());
    try std.testing.expectEqual(@as(i16, 0), oc_storage_selected_partition_index());
    const expected_partition: BaremetalStoragePartitionInfo = .{
        .scheme = @intFromEnum(ata_pio_disk.PartitionScheme.mbr),
        .reserved0 = .{ 0, 0, 0 },
        .start_lba = ata_probe_partition_start_lba,
        .sector_count = ata_probe_partition_sector_count,
    };
    try std.testing.expectEqual(expected_partition, oc_storage_partition_info(0));

    try std.testing.expectEqual(@as(i16, abi.result_ok), oc_storage_write_pattern(6, 1, 0x55));
    try std.testing.expectEqual(@as(u8, 0x55), oc_storage_read_byte(6, 0));
    try std.testing.expectEqual(@as(u8, 0x55), ata_pio_disk.testReadMockByteRaw(ata_probe_partition_start_lba + 6, 0));
    try std.testing.expectEqual(@as(i16, abi.result_ok), oc_storage_flush());
}

test "baremetal storage export surface enumerates and selects ata partitions" {
    resetBaremetalRuntimeForTest();
    ata_pio_disk.testEnableMockDevice(16384);
    ata_pio_disk.testInstallMockMbrPartition(ata_probe_partition_start_lba, ata_probe_partition_sector_count, 0x83);
    ata_pio_disk.testInstallMockMbrPartitionAt(1, ata_probe_secondary_partition_start_lba, ata_probe_secondary_partition_sector_count, 0x83);
    defer ata_pio_disk.testDisableMockDevice();

    oc_storage_init();

    try std.testing.expectEqual(@as(u32, 2), oc_storage_partition_count());
    try std.testing.expectEqual(@as(i16, 0), oc_storage_selected_partition_index());
    try std.testing.expectEqual(ata_probe_partition_start_lba, oc_storage_logical_base_lba());
    const expected_primary: BaremetalStoragePartitionInfo = .{
        .scheme = @intFromEnum(ata_pio_disk.PartitionScheme.mbr),
        .reserved0 = .{ 0, 0, 0 },
        .start_lba = ata_probe_partition_start_lba,
        .sector_count = ata_probe_partition_sector_count,
    };
    const expected_secondary: BaremetalStoragePartitionInfo = .{
        .scheme = @intFromEnum(ata_pio_disk.PartitionScheme.mbr),
        .reserved0 = .{ 0, 0, 0 },
        .start_lba = ata_probe_secondary_partition_start_lba,
        .sector_count = ata_probe_secondary_partition_sector_count,
    };
    try std.testing.expectEqual(expected_primary, oc_storage_partition_info(0));
    try std.testing.expectEqual(expected_secondary, oc_storage_partition_info(1));
    try std.testing.expectEqual(std.mem.zeroes(BaremetalStoragePartitionInfo), oc_storage_partition_info(2));

    try std.testing.expectEqual(@as(i16, abi.result_ok), oc_storage_select_partition(1));
    try std.testing.expectEqual(@as(i16, 1), oc_storage_selected_partition_index());
    try std.testing.expectEqual(ata_probe_secondary_partition_start_lba, oc_storage_logical_base_lba());
    try std.testing.expectEqual(@as(u32, ata_probe_secondary_partition_sector_count), oc_storage_state_ptr().block_count);

    try std.testing.expectEqual(@as(i16, abi.result_invalid_argument), oc_storage_select_partition(9));
}

test "baremetal storage partition selection rebinds tool layout and filesystem surfaces" {
    resetBaremetalRuntimeForTest();
    ata_pio_disk.testEnableMockDevice(16384);
    ata_pio_disk.testInstallMockMbrPartition(ata_probe_partition_start_lba, ata_probe_partition_sector_count, 0x83);
    ata_pio_disk.testInstallMockMbrPartitionAt(1, ata_probe_secondary_partition_start_lba, ata_probe_secondary_partition_sector_count, 0x83);
    defer ata_pio_disk.testDisableMockDevice();

    oc_storage_init();

    try std.testing.expectEqual(@as(i16, abi.result_ok), oc_tool_layout_init());
    try std.testing.expectEqual(@as(i16, abi.result_ok), oc_tool_slot_write_pattern(ata_probe_tool_slot_id, ata_probe_tool_slot_byte_len, ata_probe_tool_slot_seed));
    try std.testing.expectEqual(@as(i16, abi.result_ok), oc_filesystem_init());
    try filesystem.createDirPath(ata_probe_filesystem_dir);
    try filesystem.writeFile(ata_probe_filesystem_path, ata_probe_filesystem_payload, 77);
    try std.testing.expect(probeFilesystemContent(ata_probe_filesystem_path, ata_probe_filesystem_payload));

    try std.testing.expectEqual(@as(i16, abi.result_ok), oc_storage_select_partition(1));
    try std.testing.expectEqual(@as(i16, 1), oc_storage_selected_partition_index());
    try std.testing.expectEqual(@as(u8, 0), oc_tool_layout_state_ptr().formatted);
    try std.testing.expectEqual(@as(u8, 0), oc_filesystem_state_ptr().formatted);
    try std.testing.expectEqual(@as(u8, 0), oc_filesystem_state_ptr().mounted);

    try std.testing.expectEqual(@as(i16, abi.result_ok), oc_tool_layout_format());
    try std.testing.expectEqual(@as(i16, abi.result_ok), oc_tool_slot_write_pattern(ata_probe_tool_slot_id, ata_probe_tool_slot_byte_len, ata_probe_secondary_tool_slot_seed));
    try std.testing.expectEqual(@as(i16, abi.result_ok), oc_filesystem_format());
    try filesystem.createDirPath(ata_probe_filesystem_dir);
    try filesystem.writeFile(ata_probe_filesystem_path, ata_probe_secondary_filesystem_payload, 88);
    try std.testing.expect(probeFilesystemContent(ata_probe_filesystem_path, ata_probe_secondary_filesystem_payload));

    try std.testing.expectEqual(@as(i16, abi.result_ok), oc_storage_select_partition(0));
    try std.testing.expectEqual(@as(i16, abi.result_ok), oc_tool_layout_init());
    try std.testing.expectEqual(@as(i16, abi.result_ok), oc_filesystem_init());
    try std.testing.expectEqual(@as(u8, ata_probe_tool_slot_seed), oc_tool_slot_byte(ata_probe_tool_slot_id, 0));
    try std.testing.expect(probeFilesystemContent(ata_probe_filesystem_path, ata_probe_filesystem_payload));

    try std.testing.expectEqual(@as(i16, abi.result_ok), oc_storage_select_partition(1));
    try std.testing.expectEqual(@as(i16, abi.result_ok), oc_tool_layout_init());
    try std.testing.expectEqual(@as(i16, abi.result_ok), oc_filesystem_init());
    try std.testing.expectEqual(@as(u8, ata_probe_secondary_tool_slot_seed), oc_tool_slot_byte(ata_probe_tool_slot_id, 0));
    try std.testing.expect(probeFilesystemContent(ata_probe_filesystem_path, ata_probe_secondary_filesystem_payload));
}

test "baremetal virtio block probe validates raw, tool layout, and filesystem persistence" {
    resetBaremetalRuntimeForTest();
    virtio_block.testEnableMockDevice(8192);
    defer virtio_block.testDisableMockDevice();

    try runVirtioBlockProbe();

    const storage = oc_storage_state_ptr();
    try std.testing.expectEqual(@as(u8, abi.storage_backend_virtio_block), storage.backend);
    try std.testing.expectEqual(@as(u8, 1), storage.mounted);
    try std.testing.expectEqual(@as(u32, 0), oc_storage_logical_base_lba());
    try std.testing.expectEqual(@as(u32, 0), oc_storage_partition_count());
    try std.testing.expectEqual(@as(i16, -1), oc_storage_selected_partition_index());
    try std.testing.expectEqual(@as(u8, virtio_block_probe_raw_seed), oc_storage_read_byte(virtio_block_probe_raw_lba, 0));
    try std.testing.expectEqual(@as(u8, virtio_block_probe_raw_seed +% 1), oc_storage_read_byte(virtio_block_probe_raw_lba, 1));

    const slot = oc_tool_layout_slot(virtio_block_probe_tool_slot_id);
    try std.testing.expectEqual(@as(u8, virtio_block_probe_tool_slot_seed), oc_tool_slot_byte(virtio_block_probe_tool_slot_id, 0));
    try std.testing.expectEqual(@as(u8, virtio_block_probe_tool_slot_seed), oc_storage_read_byte(slot.start_lba, 0));
    try std.testing.expectEqual(@as(u8, abi.storage_backend_virtio_block), oc_filesystem_state_ptr().active_backend);
    try std.testing.expect(probeFilesystemContent(virtio_block_probe_filesystem_path, virtio_block_probe_filesystem_payload));
}

    try std.testing.expectEqual(@as(u8, 1), storage.mounted);
    try std.testing.expectEqual(@as(u8, abi.storage_backend_virtio_block), oc_filesystem_state_ptr().active_backend);

    const loader = try filesystem.readFileAlloc(std.testing.allocator, disk_installer.loader_cfg_path, 160);
    defer std.testing.allocator.free(loader);
    try std.testing.expect(std.mem.indexOf(u8, loader, "backend=virtio_block") != null);

    const manifest = try filesystem.readFileAlloc(std.testing.allocator, disk_installer.install_manifest_path, 192);
    defer std.testing.allocator.free(manifest);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "backend=virtio_block") != null);

test "baremetal virtio block mount probe persists mounted alias paths" {
    resetBaremetalRuntimeForTest();
    virtio_block.testEnableMockDevice(16384);
    defer virtio_block.testDisableMockDevice();

    try runVirtioBlockMountProbe();

    const boot_loader = try filesystem.readFileAlloc(std.testing.allocator, "/mnt/boot/loader.cfg", 160);
    defer std.testing.allocator.free(boot_loader);
    try std.testing.expect(std.mem.indexOf(u8, boot_loader, "backend=virtio_block") != null);

    const runtime_payload = try filesystem.readFileAlloc(std.testing.allocator, "/mnt/runtime/state/mounted-via-alias.txt", 64);
    defer std.testing.allocator.free(runtime_payload);
    try std.testing.expectEqualStrings("mounted-via-alias", runtime_payload);

    const root_listing = try filesystem.listDirectoryAlloc(std.testing.allocator, "/", 256);
    defer std.testing.allocator.free(root_listing);
    try std.testing.expect(std.mem.indexOf(u8, root_listing, "dir mnt\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, root_listing, "dir tmp\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, root_listing, "dir proc\n") != null);

    const proc_version = try filesystem.readFileAlloc(std.testing.allocator, "/proc/version", 256);
    defer std.testing.allocator.free(proc_version);
    try std.testing.expect(std.mem.indexOf(u8, proc_version, "project=ZAR-Zig-Agent-Runtime") != null);

    const storage_state = try filesystem.readFileAlloc(std.testing.allocator, "/sys/storage/state", 256);
    defer std.testing.allocator.free(storage_state);
    try std.testing.expect(std.mem.indexOf(u8, storage_state, "backend=virtio_block") != null);
    try std.testing.expect(std.mem.indexOf(u8, storage_state, "detected_filesystem=zarfs") != null);

    const storage_backends = try filesystem.readFileAlloc(std.testing.allocator, "/sys/storage/backends", 1024);
    defer std.testing.allocator.free(storage_backends);
    try std.testing.expect(std.mem.indexOf(u8, storage_backends, "backend[0]=name=ram_disk backend=ram_disk available=1 selected=0 mounted=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, storage_backends, "backend[2]=name=virtio_block backend=virtio_block available=1 selected=1 mounted=1 preferred_order=2 filesystem=zarfs") != null);

    const storage_filesystems = try filesystem.readFileAlloc(std.testing.allocator, "/sys/storage/filesystems", 512);
    defer std.testing.allocator.free(storage_filesystems);
    try std.testing.expect(std.mem.indexOf(u8, storage_filesystems, "filesystem=ext2 detect=1 mount=1 write=0 source=zar_bounded_read_only") != null);
    try std.testing.expect(std.mem.indexOf(u8, storage_filesystems, "filesystem=fat32 detect=1 mount=1 write=1 source=zar_bounded_writable_one_level_83") != null);

    const storage_registry_text = try filesystem.readFileAlloc(std.testing.allocator, "/sys/storage/registry", 2048);
    defer std.testing.allocator.free(storage_registry_text);
    try std.testing.expect(std.mem.indexOf(u8, storage_registry_text, "name=root path=/ target=/ layer=persistent backend=virtio_block filesystem=zarfs") != null);
    try std.testing.expect(std.mem.indexOf(u8, storage_registry_text, "name=cache path=/mnt/cache target=/tmp/cache layer=tmpfs backend=none filesystem=tmpfs") != null);

    try std.testing.expectEqual(error.FileNotFound, filesystem.readFileAlloc(std.testing.allocator, "/mnt/cache/volatile.txt", 64));
}

test "baremetal virtio block ext2 mount probe exposes read only external alias" {
    resetBaremetalRuntimeForTest();
    virtio_block.testEnableMockDevice(16384);
    defer virtio_block.testDisableMockDevice();

    try runVirtioBlockExt2MountProbe();

    const listing = try filesystem.listDirectoryAlloc(std.testing.allocator, "/mnt/external", 256);
    defer std.testing.allocator.free(listing);
    try std.testing.expectEqualStrings("file HELLO.TXT 15\n", listing);

    const payload = try filesystem.readFileAlloc(std.testing.allocator, "/mnt/external/HELLO.TXT", 64);
    defer std.testing.allocator.free(payload);
    try std.testing.expectEqualStrings(ext2_ro.test_file_payload, payload);
}

test "baremetal virtio block fat32 mount probe exposes writable external alias" {
    resetBaremetalRuntimeForTest();
    virtio_block.testEnableMockDevice(16384);
    defer virtio_block.testDisableMockDevice();

    try runVirtioBlockFat32MountProbe();

    const listing = try filesystem.listDirectoryAlloc(std.testing.allocator, "/mnt/external", 256);
    defer std.testing.allocator.free(listing);
    try std.testing.expect(std.mem.indexOf(u8, listing, "file HELLO.TXT 16\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, listing, "dir DATA\n") != null);

    const payload = try filesystem.readFileAlloc(std.testing.allocator, "/mnt/external/HELLO.TXT", 64);
    defer std.testing.allocator.free(payload);
    try std.testing.expectEqualStrings(fat32_ro.test_file_payload, payload);

    const nested_listing = try filesystem.listDirectoryAlloc(std.testing.allocator, "/mnt/external/DATA", 256);
    defer std.testing.allocator.free(nested_listing);
    try std.testing.expect(std.mem.indexOf(u8, nested_listing, "file NOTE.TXT 23\n") != null);

    const nested_payload = try filesystem.readFileAlloc(std.testing.allocator, "/mnt/external/DATA/NOTE.TXT", 64);
    defer std.testing.allocator.free(nested_payload);
    try std.testing.expectEqualStrings(fat32_ro.test_nested_file_payload, nested_payload);

    try filesystem.writeFile("/mnt/external/WRITE.TXT", "host-fat32-write", 70);
    const written = try filesystem.readFileAlloc(std.testing.allocator, "/mnt/external/WRITE.TXT", 64);
    defer std.testing.allocator.free(written);
    try std.testing.expectEqualStrings("host-fat32-write", written);
    try filesystem.deleteFile("/mnt/external/WRITE.TXT", 71);
    try std.testing.expectEqual(error.FileNotFound, filesystem.readFileAlloc(std.testing.allocator, "/mnt/external/WRITE.TXT", 64));

    try filesystem.writeFile("/mnt/external/DATA/WRITE.TXT", "host-fat32-nested", 72);
    const nested_written = try filesystem.readFileAlloc(std.testing.allocator, "/mnt/external/DATA/WRITE.TXT", 64);
    defer std.testing.allocator.free(nested_written);
    try std.testing.expectEqualStrings("host-fat32-nested", nested_written);
    try filesystem.deleteFile("/mnt/external/DATA/WRITE.TXT", 73);
    try std.testing.expectEqual(error.FileNotFound, filesystem.readFileAlloc(std.testing.allocator, "/mnt/external/DATA/WRITE.TXT", 64));

    try filesystem.createDirPath("/mnt/external/CACHE");
    {
        const root_listing = try filesystem.listDirectoryAlloc(std.testing.allocator, "/mnt/external", 256);
        defer std.testing.allocator.free(root_listing);
        try std.testing.expect(std.mem.indexOf(u8, root_listing, "dir CACHE\n") != null);
    }

    try filesystem.writeFile("/mnt/external/CACHE/LOG.TXT", "host-fat32-dir", 74);
    const dir_written = try filesystem.readFileAlloc(std.testing.allocator, "/mnt/external/CACHE/LOG.TXT", 64);
    defer std.testing.allocator.free(dir_written);
    try std.testing.expectEqualStrings("host-fat32-dir", dir_written);

    try filesystem.createDirPath("/mnt/external/DATA/ARCHIVE");
    const nested_dir_listing = try filesystem.listDirectoryAlloc(std.testing.allocator, "/mnt/external/DATA", 256);
    defer std.testing.allocator.free(nested_dir_listing);
    try std.testing.expect(std.mem.indexOf(u8, nested_dir_listing, "dir ARCHIVE\n") != null);

    try filesystem.deleteTree("/mnt/external/CACHE", 75);
    try std.testing.expectEqual(error.FileNotFound, filesystem.readFileAlloc(std.testing.allocator, "/mnt/external/CACHE/LOG.TXT", 64));
    {
        const root_listing = try filesystem.listDirectoryAlloc(std.testing.allocator, "/mnt/external", 256);
        defer std.testing.allocator.free(root_listing);
        try std.testing.expect(std.mem.indexOf(u8, root_listing, "dir CACHE\n") == null);
    }

    try filesystem.deleteTree("/mnt/external/DATA/ARCHIVE", 76);
    const nested_dir_listing_after_delete = try filesystem.listDirectoryAlloc(std.testing.allocator, "/mnt/external/DATA", 256);
    defer std.testing.allocator.free(nested_dir_listing_after_delete);
    try std.testing.expect(std.mem.indexOf(u8, nested_dir_listing_after_delete, "dir ARCHIVE\n") == null);
}

test "baremetal storage backend info export mirrors registry state" {
    resetBaremetalRuntimeForTest();
    virtio_block.testEnableMockDevice(256);
    defer virtio_block.testDisableMockDevice();

    oc_storage_init();

    try std.testing.expectEqual(@as(u32, 3), oc_storage_backend_count());
    const ram = oc_storage_backend_info(0);
    const virt = oc_storage_backend_info(2);
    try std.testing.expectEqual(@as(u8, abi.storage_backend_ram_disk), ram.backend);
    try std.testing.expectEqual(@as(u8, 1), ram.available);
    try std.testing.expectEqual(@as(u8, abi.storage_backend_virtio_block), virt.backend);
    try std.testing.expectEqual(@as(u8, 1), virt.available);
    try std.testing.expectEqual(@as(u8, 1), virt.selected);
    try std.testing.expectEqual(@as(u8, abi.storage_filesystem_kind_unknown), virt.filesystem_kind);
}

test "baremetal filesystem mount control exports bind and remove aliases" {
    resetBaremetalRuntimeForTest();

    try std.testing.expectEqual(@as(i16, abi.result_ok), oc_filesystem_format());
    try std.testing.expectEqual(@as(u32, 0), oc_filesystem_mount_count());
    try std.testing.expectEqual(
        @as(i16, abi.result_ok),
        oc_filesystem_bind_mount("cache".ptr, 5, "/tmp/cache".ptr, 10, 55),
    );

    try std.testing.expectEqual(@as(u32, 1), oc_filesystem_mount_count());
    const mount = oc_filesystem_mount_entry(0);
    try std.testing.expectEqual(@as(u8, 5), mount.name_len);
    try std.testing.expectEqual(@as(u16, 10), mount.target_len);
    try std.testing.expectEqual(@as(u64, 55), mount.modified_tick);
    try std.testing.expectEqualStrings("cache", mount.name[0..mount.name_len]);
    try std.testing.expectEqualStrings("/tmp/cache", mount.target[0..mount.target_len]);

    try filesystem.createDirPath("/mnt/cache");
    try filesystem.writeFile("/mnt/cache/state.txt", "mounted-cache", 56);
    const payload = try filesystem.readFileAlloc(std.testing.allocator, "/mnt/cache/state.txt", 64);
    defer std.testing.allocator.free(payload);
    try std.testing.expectEqualStrings("mounted-cache", payload);

    try std.testing.expectEqual(
        @as(i16, abi.result_ok),
        oc_filesystem_remove_mount("cache".ptr, 5, 57),
    );
    try std.testing.expectEqual(@as(u32, 0), oc_filesystem_mount_count());
}

test "baremetal virtio block mount control probe persists exported alias state" {
    resetBaremetalRuntimeForTest();
    virtio_block.testEnableMockDevice(256);
    defer virtio_block.testDisableMockDevice();

    try runVirtioBlockMountControlProbe();
}

test "baremetal tool layout persists patterned tool slot payloads on ram disk" {
    resetBaremetalRuntimeForTest();

    try std.testing.expectEqual(@as(i16, abi.result_ok), oc_tool_layout_init());
    const layout = oc_tool_layout_state_ptr();
    try std.testing.expectEqual(@as(u32, abi.tool_layout_magic), layout.magic);
    try std.testing.expectEqual(@as(u8, 1), layout.formatted);
    try std.testing.expectEqual(@as(u16, tool_layout.slot_count), layout.slot_count);
    try std.testing.expectEqual(@as(u32, tool_layout.slot_data_lba), layout.slot_data_lba);

    try std.testing.expectEqual(@as(i16, abi.result_ok), oc_tool_slot_write_pattern(1, 1000, 0x30));
    const slot = oc_tool_layout_slot(1);
    try std.testing.expectEqual(@as(u32, 1), layout.write_count);
    try std.testing.expectEqual(@as(u32, 2), slot.block_count);
    try std.testing.expectEqual(@as(u32, 1000), slot.byte_len);
    try std.testing.expectEqual(tool_layout.tool_slot_flag_valid, slot.flags);
    try std.testing.expectEqual(@as(u8, 0x30), oc_tool_slot_byte(1, 0));
    try std.testing.expectEqual(@as(u8, 0x31), oc_tool_slot_byte(1, 1));
    try std.testing.expectEqual(@as(u8, 0x30), oc_tool_slot_byte(1, 512));
    try std.testing.expectEqual(@as(u8, 0x30), oc_storage_read_byte(slot.start_lba, 0));

    try std.testing.expectEqual(@as(i16, abi.result_ok), oc_tool_slot_clear(1));
    const cleared = oc_tool_layout_slot(1);
    try std.testing.expectEqual(@as(u32, 1), layout.clear_count);
    try std.testing.expectEqual(@as(u32, 0), cleared.block_count);
    try std.testing.expectEqual(@as(u32, 0), cleared.byte_len);
    try std.testing.expectEqual(@as(u32, 0), cleared.flags);
    try std.testing.expectEqual(@as(u8, 0), oc_tool_slot_byte(1, 0));
}

test "baremetal filesystem persists path-based files on the ram disk" {
    resetBaremetalRuntimeForTest();

    try std.testing.expectEqual(@as(i16, abi.result_ok), oc_filesystem_init());
    const fs_state = oc_filesystem_state_ptr();
    try std.testing.expectEqual(@as(u32, abi.filesystem_magic), fs_state.magic);
    try std.testing.expectEqual(@as(u8, 1), fs_state.formatted);
    try std.testing.expectEqual(@as(u8, abi.storage_backend_ram_disk), fs_state.active_backend);

    const io = if (builtin.os.tag == .freestanding) undefined else std.Io.Threaded.global_single_threaded.io();
    if (builtin.os.tag == .freestanding) {
        try pal_fs.createDirPath(io, "/runtime/state");
        try pal_fs.writeFile(io, "/runtime/state/agent.json", "{\"ok\":true}");
        const stat = try pal_fs.statNoFollow(io, "/runtime/state/agent.json");
        try std.testing.expectEqual(@as(std.Io.File.Kind, .file), stat.kind);
        try std.testing.expectEqual(@as(u64, 11), stat.size);

        const content = try pal_fs.readFileAlloc(io, std.testing.allocator, "/runtime/state/agent.json", 64);
        defer std.testing.allocator.free(content);
        try std.testing.expectEqualStrings("{\"ok\":true}", content);
    } else {
        try filesystem.createDirPath("/runtime/state");
        try filesystem.writeFile("/runtime/state/agent.json", "{\"ok\":true}", status.ticks);
        const stat = try filesystem.statNoFollow("/runtime/state/agent.json");
        try std.testing.expectEqual(@as(std.Io.File.Kind, .file), stat.kind);
        try std.testing.expectEqual(@as(u64, 11), stat.size);

        const content = try filesystem.readFileAlloc(std.testing.allocator, "/runtime/state/agent.json", 64);
        defer std.testing.allocator.free(content);
        try std.testing.expectEqualStrings("{\"ok\":true}", content);
    }

    try std.testing.expectEqual(@as(u16, 2), fs_state.dir_entries);
    try std.testing.expectEqual(@as(u16, 1), fs_state.file_entries);

    filesystem.resetForTest();
    try filesystem.init();
    const reloaded = try filesystem.readFileAlloc(std.testing.allocator, "/runtime/state/agent.json", 64);
    defer std.testing.allocator.free(reloaded);
    try std.testing.expectEqualStrings("{\"ok\":true}", reloaded);
}

test "baremetal filesystem persists path-based files on ata-backed storage" {
    resetBaremetalRuntimeForTest();
    ata_pio_disk.testEnableMockDevice(8192);
    ata_pio_disk.testInstallMockMbrPartition(ata_probe_partition_start_lba, ata_probe_partition_sector_count, 0x83);
    defer ata_pio_disk.testDisableMockDevice();

    try std.testing.expectEqual(@as(i16, abi.result_ok), oc_filesystem_init());
    try std.testing.expectEqual(ata_probe_partition_start_lba, ata_pio_disk.logicalBaseLba());
    try filesystem.createDirPath("/tools/cache");
    try filesystem.writeFile("/tools/cache/tool.txt", "edge", 99);

    const fs_state = oc_filesystem_state_ptr();
    try std.testing.expectEqual(@as(u8, abi.storage_backend_ata_pio), fs_state.active_backend);
    try std.testing.expectEqual(@as(u16, 2), fs_state.dir_entries);
    try std.testing.expectEqual(@as(u16, 1), fs_state.file_entries);

    filesystem.resetForTest();
    try filesystem.init();
    const stat = try filesystem.statNoFollow("/tools/cache/tool.txt");
    try std.testing.expectEqual(@as(std.Io.File.Kind, .file), stat.kind);
    try std.testing.expectEqual(@as(u64, 4), stat.size);
    const content = try filesystem.readFileAlloc(std.testing.allocator, "/tools/cache/tool.txt", 64);
    defer std.testing.allocator.free(content);
    try std.testing.expectEqualStrings("edge", content);
}

test "baremetal ata storage probe validates raw, tool layout, and filesystem persistence" {
    resetBaremetalRuntimeForTest();
    ata_pio_disk.testEnableMockDevice(16384);
    ata_pio_disk.testInstallMockMbrPartition(ata_probe_partition_start_lba, ata_probe_partition_sector_count, 0x83);
    ata_pio_disk.testInstallMockMbrPartitionAt(1, ata_probe_secondary_partition_start_lba, ata_probe_secondary_partition_sector_count, 0x83);
    defer ata_pio_disk.testDisableMockDevice();

    try runAtaStorageProbe();

    const storage = oc_storage_state_ptr();
    try std.testing.expectEqual(@as(u8, abi.storage_backend_ata_pio), storage.backend);
    try std.testing.expectEqual(ata_probe_partition_start_lba, oc_storage_logical_base_lba());
    try std.testing.expectEqual(@as(u32, 2), oc_storage_partition_count());
    try std.testing.expectEqual(@as(i16, 0), oc_storage_selected_partition_index());
    const expected_primary: BaremetalStoragePartitionInfo = .{
        .scheme = @intFromEnum(ata_pio_disk.PartitionScheme.mbr),
        .reserved0 = .{ 0, 0, 0 },
        .start_lba = ata_probe_partition_start_lba,
        .sector_count = ata_probe_partition_sector_count,
    };
    const expected_secondary: BaremetalStoragePartitionInfo = .{
        .scheme = @intFromEnum(ata_pio_disk.PartitionScheme.mbr),
        .reserved0 = .{ 0, 0, 0 },
        .start_lba = ata_probe_secondary_partition_start_lba,
        .sector_count = ata_probe_secondary_partition_sector_count,
    };
    try std.testing.expectEqual(expected_primary, oc_storage_partition_info(0));
    try std.testing.expectEqual(expected_secondary, oc_storage_partition_info(1));
    try std.testing.expectEqual(@as(u8, 0x41), oc_storage_read_byte(ata_probe_raw_lba, 0));
    try std.testing.expectEqual(@as(u8, 0x42), oc_storage_read_byte(ata_probe_raw_lba, 1));
    try std.testing.expectEqual(@as(u8, 0x41), oc_storage_read_byte(ata_probe_raw_lba + 1, 0));
    try std.testing.expectEqual(@as(u8, 0x41), ata_pio_disk.testReadMockByteRaw(ata_probe_partition_start_lba + ata_probe_raw_lba, 0));
    try std.testing.expectEqual(@as(u8, 0x42), ata_pio_disk.testReadMockByteRaw(ata_probe_partition_start_lba + ata_probe_raw_lba, 1));
    try std.testing.expectEqual(@as(u8, 0x41), ata_pio_disk.testReadMockByteRaw(ata_probe_partition_start_lba + ata_probe_raw_lba + 1, 0));
    try std.testing.expectEqual(@as(u8, ata_probe_secondary_raw_seed), ata_pio_disk.testReadMockByteRaw(ata_probe_secondary_partition_start_lba + ata_probe_secondary_raw_lba, 0));
    try std.testing.expectEqual(@as(u8, ata_probe_secondary_raw_seed +% 1), ata_pio_disk.testReadMockByteRaw(ata_probe_secondary_partition_start_lba + ata_probe_secondary_raw_lba, 1));

    const slot = oc_tool_layout_slot(ata_probe_tool_slot_id);
    try std.testing.expectEqual(ata_probe_tool_slot_expected_lba, slot.start_lba);
    try std.testing.expectEqual(@as(u8, ata_probe_tool_slot_seed), oc_tool_slot_byte(ata_probe_tool_slot_id, 0));
    try std.testing.expectEqual(@as(u8, ata_probe_tool_slot_seed), oc_tool_slot_byte(ata_probe_tool_slot_id, 512));
    try std.testing.expectEqual(@as(u8, ata_probe_tool_slot_seed), ata_pio_disk.testReadMockByteRaw(ata_probe_partition_start_lba + slot.start_lba, 0));

    const content = try filesystem.readFileAlloc(std.testing.allocator, ata_probe_filesystem_path, 64);
    defer std.testing.allocator.free(content);
    try std.testing.expectEqualStrings(ata_probe_filesystem_payload, content);
}

test "baremetal ata gpt installer probe validates partition mount and install layout persistence" {
    resetBaremetalRuntimeForTest();
    ata_pio_disk.testEnableMockDevice(16384);
    ata_pio_disk.testInstallMockProtectiveGptPartition(ata_gpt_probe_partition_start_lba, ata_gpt_probe_partition_sector_count);
    defer ata_pio_disk.testDisableMockDevice();

    try runAtaGptInstallerProbe();

    const storage = oc_storage_state_ptr();
    try std.testing.expectEqual(@as(u8, abi.storage_backend_ata_pio), storage.backend);
    try std.testing.expectEqual(ata_gpt_probe_partition_start_lba, ata_pio_disk.logicalBaseLba());
    try std.testing.expectEqual(ata_gpt_probe_partition_sector_count, storage.block_count);
    try std.testing.expectEqual(@as(u8, ata_gpt_probe_raw_seed), oc_storage_read_byte(ata_gpt_probe_raw_lba, 0));
    try std.testing.expectEqual(@as(u8, ata_gpt_probe_raw_seed), ata_pio_disk.testReadMockByteRaw(ata_gpt_probe_partition_start_lba + ata_gpt_probe_raw_lba, 0));

    const manifest = try filesystem.readFileAlloc(std.testing.allocator, disk_installer.install_manifest_path, 192);
    defer std.testing.allocator.free(manifest);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "logical_base_lba=2048") != null);

