const e1000 = @import("baremetal/e1000.zig");
const rtl8139 = @import("baremetal/rtl8139.zig");
const virtio_net = @import("baremetal/virtio_net.zig");
const storage_backend = @import("baremetal/storage_backend.zig");
const storage_backend_registry = @import("baremetal/storage_backend_registry.zig");
const storage_registry = @import("baremetal/storage_registry.zig");
const filesystem = @import("baremetal/filesystem.zig");
const qemu_e1000_probe_ok_code: u8 = 0x45;
const qemu_e1000_arp_probe_ok_code: u8 = 0x46;
const qemu_e1000_ipv4_probe_ok_code: u8 = 0x47;
const qemu_e1000_udp_probe_ok_code: u8 = 0x48;
const qemu_e1000_tcp_probe_ok_code: u8 = 0x49;
const qemu_e1000_http_post_probe_ok_code: u8 = 0x4A;
const qemu_e1000_https_post_probe_ok_code: u8 = 0x4B;
const qemu_e1000_tool_service_probe_ok_code: u8 = 0x4C;
const qemu_e1000_dhcp_probe_ok_code: u8 = 0x4D;
const qemu_e1000_dns_probe_ok_code: u8 = 0x4E;
const qemu_e1000_full_stack_probe_ok_code: u8 = 0x5E;
const qemu_virtio_net_probe_ok_code: u8 = 0x4F;
const qemu_virtio_net_arp_probe_ok_code: u8 = 0x50;
const qemu_virtio_net_ipv4_probe_ok_code: u8 = 0x51;
const qemu_virtio_net_udp_probe_ok_code: u8 = 0x52;
const qemu_virtio_net_tcp_probe_ok_code: u8 = 0x53;
const qemu_virtio_net_dhcp_probe_ok_code: u8 = 0x54;
const qemu_virtio_net_dns_probe_ok_code: u8 = 0x55;
const qemu_virtio_net_http_post_probe_ok_code: u8 = 0x56;
const qemu_virtio_net_https_post_probe_ok_code: u8 = 0x57;
const qemu_virtio_net_tool_service_probe_ok_code: u8 = 0x58;
const qemu_virtio_block_probe_ok_code: u8 = 0x4F;
const qemu_virtio_block_installer_probe_ok_code: u8 = 0x59;
        pub const e1000_probe: bool = false;
        pub const e1000_arp_probe: bool = false;
        pub const e1000_ipv4_probe: bool = false;
        pub const e1000_udp_probe: bool = false;
        pub const e1000_tcp_probe: bool = false;
        pub const e1000_dhcp_probe: bool = false;
        pub const e1000_dns_probe: bool = false;
        pub const e1000_http_post_probe: bool = false;
        pub const e1000_https_post_probe: bool = false;
        pub const e1000_tool_service_probe: bool = false;
        pub const virtio_net_probe: bool = false;
        pub const virtio_net_arp_probe: bool = false;
        pub const virtio_net_ipv4_probe: bool = false;
        pub const virtio_net_udp_probe: bool = false;
        pub const virtio_net_tcp_probe: bool = false;
        pub const virtio_net_dhcp_probe: bool = false;
        pub const virtio_net_dns_probe: bool = false;
        pub const virtio_net_http_post_probe: bool = false;
        pub const virtio_net_https_post_probe: bool = false;
        pub const virtio_net_tool_service_probe: bool = false;
        pub const rtl8139_probe: bool = false;
        pub const rtl8139_arp_probe: bool = false;
        pub const rtl8139_ipv4_probe: bool = false;
        pub const rtl8139_udp_probe: bool = false;
        pub const rtl8139_tcp_probe: bool = false;
        pub const rtl8139_dhcp_probe: bool = false;
        pub const rtl8139_dns_probe: bool = false;
        pub const rtl8139_http_post_probe: bool = false;
        pub const rtl8139_https_post_probe: bool = false;
        pub const rtl8139_runtime_service_probe: bool = false;
        pub const tool_exec_probe: bool = false;
        pub const tool_runtime_probe: bool = false;
        pub const rtl8139_gateway_probe: bool = false;
        pub const ata_gpt_installer_probe: bool = false;
        pub const virtio_gpu_display_probe: bool = false;
        pub const virtio_block_probe: bool = false;
        pub const virtio_block_installer_probe: bool = false;
const e1000_probe_enabled: bool = if (@hasDecl(build_options, "e1000_probe")) build_options.e1000_probe else false;
const e1000_arp_probe_enabled: bool = if (@hasDecl(build_options, "e1000_arp_probe")) build_options.e1000_arp_probe else false;
const e1000_ipv4_probe_enabled: bool = if (@hasDecl(build_options, "e1000_ipv4_probe")) build_options.e1000_ipv4_probe else false;
const e1000_udp_probe_enabled: bool = if (@hasDecl(build_options, "e1000_udp_probe")) build_options.e1000_udp_probe else false;
const e1000_tcp_probe_enabled: bool = if (@hasDecl(build_options, "e1000_tcp_probe")) build_options.e1000_tcp_probe else false;
const e1000_dhcp_probe_enabled: bool = if (@hasDecl(build_options, "e1000_dhcp_probe")) build_options.e1000_dhcp_probe else false;
const e1000_dns_probe_enabled: bool = if (@hasDecl(build_options, "e1000_dns_probe")) build_options.e1000_dns_probe else false;
const e1000_http_post_probe_enabled: bool = if (@hasDecl(build_options, "e1000_http_post_probe")) build_options.e1000_http_post_probe else false;
const e1000_https_post_probe_enabled: bool = if (@hasDecl(build_options, "e1000_https_post_probe")) build_options.e1000_https_post_probe else false;
const e1000_tool_service_probe_enabled: bool = if (@hasDecl(build_options, "e1000_tool_service_probe")) build_options.e1000_tool_service_probe else false;
const e1000_full_stack_probe_enabled: bool = if (@hasDecl(build_options, "e1000_full_stack_probe")) build_options.e1000_full_stack_probe else false;
const virtio_net_probe_enabled: bool = if (@hasDecl(build_options, "virtio_net_probe")) build_options.virtio_net_probe else false;
const virtio_net_arp_probe_enabled: bool = if (@hasDecl(build_options, "virtio_net_arp_probe")) build_options.virtio_net_arp_probe else false;
const virtio_net_ipv4_probe_enabled: bool = if (@hasDecl(build_options, "virtio_net_ipv4_probe")) build_options.virtio_net_ipv4_probe else false;
const virtio_net_udp_probe_enabled: bool = if (@hasDecl(build_options, "virtio_net_udp_probe")) build_options.virtio_net_udp_probe else false;
const virtio_net_tcp_probe_enabled: bool = if (@hasDecl(build_options, "virtio_net_tcp_probe")) build_options.virtio_net_tcp_probe else false;
const virtio_net_dhcp_probe_enabled: bool = if (@hasDecl(build_options, "virtio_net_dhcp_probe")) build_options.virtio_net_dhcp_probe else false;
const virtio_net_dns_probe_enabled: bool = if (@hasDecl(build_options, "virtio_net_dns_probe")) build_options.virtio_net_dns_probe else false;
const virtio_net_http_post_probe_enabled: bool = if (@hasDecl(build_options, "virtio_net_http_post_probe")) build_options.virtio_net_http_post_probe else false;
const virtio_net_https_post_probe_enabled: bool = if (@hasDecl(build_options, "virtio_net_https_post_probe")) build_options.virtio_net_https_post_probe else false;
const virtio_net_tool_service_probe_enabled: bool = if (@hasDecl(build_options, "virtio_net_tool_service_probe")) build_options.virtio_net_tool_service_probe else false;
const rtl8139_probe_enabled: bool = build_options.rtl8139_probe;
const rtl8139_arp_probe_enabled: bool = build_options.rtl8139_arp_probe;
const rtl8139_ipv4_probe_enabled: bool = build_options.rtl8139_ipv4_probe;
const rtl8139_udp_probe_enabled: bool = build_options.rtl8139_udp_probe;
const rtl8139_tcp_probe_enabled: bool = build_options.rtl8139_tcp_probe;
const rtl8139_dhcp_probe_enabled: bool = build_options.rtl8139_dhcp_probe;
const rtl8139_dns_probe_enabled: bool = build_options.rtl8139_dns_probe;
const rtl8139_http_post_probe_enabled: bool = if (@hasDecl(build_options, "rtl8139_http_post_probe")) build_options.rtl8139_http_post_probe else false;
const rtl8139_https_post_probe_enabled: bool = if (@hasDecl(build_options, "rtl8139_https_post_probe")) build_options.rtl8139_https_post_probe else false;
const rtl8139_runtime_service_probe_enabled: bool = if (@hasDecl(build_options, "rtl8139_runtime_service_probe")) build_options.rtl8139_runtime_service_probe else false;
const tool_exec_probe_enabled: bool = build_options.tool_exec_probe;
const tool_runtime_probe_enabled: bool = if (@hasDecl(build_options, "tool_runtime_probe")) build_options.tool_runtime_probe else false;
const rtl8139_gateway_probe_enabled: bool = build_options.rtl8139_gateway_probe;
const ata_gpt_installer_probe_enabled: bool = if (@hasDecl(build_options, "ata_gpt_installer_probe")) build_options.ata_gpt_installer_probe else false;
const virtio_gpu_display_probe_enabled: bool = if (@hasDecl(build_options, "virtio_gpu_display_probe")) build_options.virtio_gpu_display_probe else false;
const virtio_block_probe_enabled: bool = if (@hasDecl(build_options, "virtio_block_probe")) build_options.virtio_block_probe else false;
const virtio_block_installer_probe_enabled: bool = if (@hasDecl(build_options, "virtio_block_installer_probe")) build_options.virtio_block_installer_probe else false;
const E1000ProbeError = error{
    UnsupportedPlatform,
    DeviceNotFound,
    MissingMmioBar,
    MissingIoBar,
    ResetTimeout,
    AutoReadTimeout,
    EepromReadFailed,
    EepromChecksumMismatch,
    MacReadFailed,
    RingProgramFailed,
    StateMagicMismatch,
    BackendMismatch,
    InitFlagMismatch,
    HardwareBackedMismatch,
    IoBaseMismatch,
    TxFailed,
    LoopbackEnableFailed,
    LinkDropped,
    LoopbackDropped,
    TxCompletedNoRxProgress,
    RxHeadAdvancedNoFrame,
    RxTimedOut,
    RxLengthMismatch,
    RxPatternMismatch,
    CounterMismatch,
};

const E1000ArpProbeError = error{
    UnsupportedPlatform,
    DeviceNotFound,
    MissingMmioBar,
    MissingIoBar,
    ResetTimeout,
    AutoReadTimeout,
    EepromReadFailed,
    EepromChecksumMismatch,
    MacReadFailed,
    RingProgramFailed,
    StateMagicMismatch,
    BackendMismatch,
    InitFlagMismatch,
    HardwareBackedMismatch,
    IoBaseMismatch,
    TxFailed,
    LinkDropped,
    TxCompletedNoRxProgress,
    RxHeadAdvancedNoFrame,
    RxTimedOut,
    PacketMissing,
    PacketDestinationMismatch,
    PacketSourceMismatch,
    PacketOperationMismatch,
    PacketSenderMismatch,
    PacketTargetMismatch,
    CounterMismatch,
};

const E1000Ipv4ProbeError = error{
    UnsupportedPlatform,
    DeviceNotFound,
    MissingMmioBar,
    MissingIoBar,
    ResetTimeout,
    AutoReadTimeout,
    EepromReadFailed,
    EepromChecksumMismatch,
    MacReadFailed,
    RingProgramFailed,
    StateMagicMismatch,
    BackendMismatch,
    InitFlagMismatch,
    HardwareBackedMismatch,
    IoBaseMismatch,
    TxFailed,
    LinkDropped,
    TxCompletedNoRxProgress,
    RxHeadAdvancedNoFrame,
    RxTimedOut,
    LastFrameTooShort,
    LastFrameNotIpv4,
    LastIpv4DecodeFailed,
    PacketMissing,
    PacketDestinationMismatch,
    PacketSourceMismatch,
    PacketProtocolMismatch,
    PacketSenderMismatch,
    PacketTargetMismatch,
    PayloadMismatch,
    FrameLengthMismatch,
    CounterMismatch,
};

const E1000UdpProbeError = error{
    UnsupportedPlatform,
    DeviceNotFound,
    MissingMmioBar,
    MissingIoBar,
    ResetTimeout,
    AutoReadTimeout,
    EepromReadFailed,
    EepromChecksumMismatch,
    MacReadFailed,
    RingProgramFailed,
    StateMagicMismatch,
    BackendMismatch,
    InitFlagMismatch,
    HardwareBackedMismatch,
    IoBaseMismatch,
    TxFailed,
    LinkDropped,
    TxCompletedNoRxProgress,
    RxHeadAdvancedNoFrame,
    RxTimedOut,
    LastFrameTooShort,
    LastFrameNotIpv4,
    LastIpv4DecodeFailed,
    LastPacketNotUdp,
    LastUdpDecodeFailed,
    PacketMissing,
    PacketDestinationMismatch,
    PacketSourceMismatch,
    PacketProtocolMismatch,
    PacketSenderMismatch,
    PacketTargetMismatch,
    PacketPortsMismatch,
    ChecksumMissing,
    PayloadMismatch,
    FrameLengthMismatch,
    CounterMismatch,
};

const E1000DhcpProbeError = error{
    UnsupportedPlatform,
    DeviceNotFound,
    MissingMmioBar,
    MissingIoBar,
    ResetTimeout,
    AutoReadTimeout,
    EepromReadFailed,
    EepromChecksumMismatch,
    MacReadFailed,
    RingProgramFailed,
    StateMagicMismatch,
    BackendMismatch,
    InitFlagMismatch,
    HardwareBackedMismatch,
    IoBaseMismatch,
    TxFailed,
    LinkDropped,
    TxCompletedNoRxProgress,
    RxHeadAdvancedNoFrame,
    RxTimedOut,
    LastFrameTooShort,
    LastFrameNotIpv4,
    LastIpv4DecodeFailed,
    LastPacketNotUdp,
    LastUdpDecodeFailed,
    LastPacketNotDhcp,
    LastDhcpDecodeFailed,
    PacketMissing,
    PacketDestinationMismatch,
    PacketSourceMismatch,
    PacketProtocolMismatch,
    PacketSenderMismatch,
    PacketTargetMismatch,
    PacketPortsMismatch,
    PacketOperationMismatch,
    TransactionIdMismatch,
    MessageTypeMismatch,
    PacketClientMacMismatch,
    ParameterRequestListMismatch,
    FlagsMismatch,
    MaxMessageSizeMismatch,
    ChecksumMissing,
    FrameLengthMismatch,
    CounterMismatch,
};

const E1000DnsProbeError = error{
    UnsupportedPlatform,
    DeviceNotFound,
    MissingMmioBar,
    MissingIoBar,
    ResetTimeout,
    AutoReadTimeout,
    EepromReadFailed,
    EepromChecksumMismatch,
    MacReadFailed,
    RingProgramFailed,
    StateMagicMismatch,
    BackendMismatch,
    InitFlagMismatch,
    HardwareBackedMismatch,
    IoBaseMismatch,
    TxFailed,
    LinkDropped,
    TxCompletedNoRxProgress,
    RxHeadAdvancedNoFrame,
    RxTimedOut,
    LastFrameTooShort,
    LastFrameNotIpv4,
    LastIpv4DecodeFailed,
    LastPacketNotUdp,
    LastUdpDecodeFailed,
    LastPacketNotDns,
    LastDnsDecodeFailed,
    PacketMissing,
    PacketDestinationMismatch,
    PacketSourceMismatch,
    PacketProtocolMismatch,
    PacketSenderMismatch,
    PacketTargetMismatch,
    PacketPortsMismatch,
    TransactionIdMismatch,
    FlagsMismatch,
    QuestionCountMismatch,
    QuestionNameMismatch,
    QuestionTypeMismatch,
    QuestionClassMismatch,
    AnswerCountMismatch,
    AnswerNameMismatch,
    AnswerTypeMismatch,
    AnswerClassMismatch,
    AnswerTtlMismatch,
    AnswerDataMismatch,
    ChecksumMissing,
    FrameLengthMismatch,
    CounterMismatch,
};

const E1000TcpProbeError = error{
    UnsupportedPlatform,
    DeviceNotFound,
    MissingMmioBar,
    MissingIoBar,
    ResetTimeout,
    AutoReadTimeout,
    EepromReadFailed,
    EepromChecksumMismatch,
    MacReadFailed,
    RingProgramFailed,
    StateMagicMismatch,
    BackendMismatch,
    InitFlagMismatch,
    HardwareBackedMismatch,
    IoBaseMismatch,
    TxFailed,
    LinkDropped,
    TxCompletedNoRxProgress,
    RxHeadAdvancedNoFrame,
    RxTimedOut,
    LastFrameTooShort,
    LastFrameNotIpv4,
    LastIpv4DecodeFailed,
    LastPacketNotTcp,
    LastTcpDecodeFailed,
    PacketMissing,
    PacketDestinationMismatch,
    PacketSourceMismatch,
    PacketProtocolMismatch,
    PacketSenderMismatch,
    PacketTargetMismatch,
    PacketPortsMismatch,
    PacketSequenceMismatch,
    PacketAcknowledgmentMismatch,
    PacketFlagsMismatch,
    WindowSizeMismatch,
    PayloadMismatch,
    FrameLengthMismatch,
    CounterMismatch,
    SessionStateMismatch,
};

const E1000HttpPostProbeError = E1000TcpProbeError || error{
    HttpPostFailed,
    HttpPostResponseMismatch,
};

const E1000HttpsPostProbeError = E1000TcpProbeError || error{
    HttpsPostFailed,
    HttpsPostResponseMismatch,
    HttpsPostNoTxProgress,
    HttpsPostNoRxProgress,
    HttpsPostTimeoutAfterRx,
    HttpsPostTlsAlert,
    HttpsPostTlsProtocolFailed,
    HttpsPostEntropyFailed,
    HttpsPostReadFailed,
    HttpsPostWriteFailed,
    HttpsPostTcpUnexpectedFlags,
    HttpsPostTcpSequenceMismatch,
    HttpsPostTcpAckMismatch,
    HttpsPostTcpWindowExceeded,
    HttpsPostTlsMessageTooLong,
    HttpsPostTlsTargetTooSmall,
    HttpsPostTlsBufferTooSmall,
    HttpsPostTlsNegativeIntoUnsigned,
    HttpsPostTlsInvalidSignature,
    HttpsPostTlsUnexpectedMessage,
    HttpsPostTlsIllegalParameter,
    HttpsPostTlsDecryptFailure,
    HttpsPostTlsRecordOverflow,
    HttpsPostTlsBadRecordMac,
    HttpsPostTlsDecryptError,
    HttpsPostTlsConnectionTruncated,
    HttpsPostTlsDecodeError,
    HttpsPostTlsAtServerHello,
    HttpsPostTlsAtEncryptedExtensions,
    HttpsPostTlsAtCertificate,
    HttpsPostTlsCertificateHostMismatch,
    HttpsPostTlsCertificateIssuerMismatch,
    HttpsPostTlsCertificateSignatureInvalid,
    HttpsPostTlsCertificateExpired,
    HttpsPostTlsCertificateNotYetValid,
    HttpsPostTlsCertificatePublicKeyInvalid,
    HttpsPostTlsCertificateTimeInvalid,
    HttpsPostTlsAtTrustChainEstablished,
    HttpsPostTlsAtCertificateVerify,
    HttpsPostTlsAtServerFinishedVerified,
    HttpsPostTlsBeforeClientFinished,
    HttpsPostTlsAfterClientFinished,
    HttpsPostTlsAfterInit,
    HttpsPostPreTlsNoSynEmit,
    HttpsPostPreTlsNoSynAck,
    HttpsPostTlsNoWriterFlush,
    HttpsPostTlsNoPayloadEmit,
    HttpsPostTlsWindowBlockedBeforeEmit,
    HttpsPostLastTxNotIpv4,
    HttpsPostLastTxIpv4DecodeFailed,
    HttpsPostLastTxNotTcp,
    HttpsPostLastTxTcpDecodeFailed,
    HttpsPostLastTxDestinationMismatch,
    HttpsPostLastTxPortsMismatch,
    HttpsPostLastTxFlagsMismatch,
};

const E1000ToolServiceProbeError = E1000TcpProbeError || error{
    ToolServiceFailed,
    ToolServiceResponseMismatch,
};

const VirtioNetProbeError = error{
    UnsupportedPlatform,
    DeviceNotFound,
    MissingVersion1,
    MissingMacFeature,
    FeaturesRejected,
    QueueUnavailable,
    QueueTooSmall,
    QueueInitFailed,
    MacReadFailed,
    StateMagicMismatch,
    BackendMismatch,
    InitFlagMismatch,
    HardwareBackedMismatch,
    IoBaseMismatch,
    TxFailed,
    RxTimedOut,
    RxLengthMismatch,
    RxPatternMismatch,
    CounterMismatch,
};

const VirtioNetProtocolInitError = error{
    UnsupportedPlatform,
    DeviceNotFound,
    MissingVersion1,
    MissingMacFeature,
    FeaturesRejected,
    QueueUnavailable,
    QueueTooSmall,
    QueueInitFailed,
    MacReadFailed,
    StateMagicMismatch,
    BackendMismatch,
    InitFlagMismatch,
    HardwareBackedMismatch,
    IoBaseMismatch,
};

const VirtioNetArpProbeError = VirtioNetProtocolInitError || error{
    TxFailed,
    RxTimedOut,
    PacketMissing,
    PacketDestinationMismatch,
    PacketSourceMismatch,
    PacketOperationMismatch,
    PacketSenderMismatch,
    PacketTargetMismatch,
    CounterMismatch,
};

const VirtioNetIpv4ProbeError = VirtioNetProtocolInitError || error{
    TxFailed,
    RxTimedOut,
    LastFrameTooShort,
    LastFrameNotIpv4,
    LastIpv4DecodeFailed,
    PacketMissing,
    PacketDestinationMismatch,
    PacketSourceMismatch,
    PacketProtocolMismatch,
    PacketSenderMismatch,
    PacketTargetMismatch,
    PayloadMismatch,
    FrameLengthMismatch,
    CounterMismatch,
};

const VirtioNetUdpProbeError = VirtioNetProtocolInitError || error{
    TxFailed,
    RxTimedOut,
    LastFrameTooShort,
    LastFrameNotIpv4,
    LastIpv4DecodeFailed,
    LastPacketNotUdp,
    LastUdpDecodeFailed,
    PacketMissing,
    PacketDestinationMismatch,
    PacketSourceMismatch,
    PacketProtocolMismatch,
    PacketSenderMismatch,
    PacketTargetMismatch,
    PacketPortsMismatch,
    ChecksumMissing,
    PayloadMismatch,
    FrameLengthMismatch,
    CounterMismatch,
};

const VirtioNetDhcpProbeError = VirtioNetProtocolInitError || error{
    TxFailed,
    RxTimedOut,
    LastFrameTooShort,
    LastFrameNotIpv4,
    LastIpv4DecodeFailed,
    LastPacketNotUdp,
    LastUdpDecodeFailed,
    LastPacketNotDhcp,
    LastDhcpDecodeFailed,
    PacketMissing,
    PacketDestinationMismatch,
    PacketSourceMismatch,
    PacketProtocolMismatch,
    PacketSenderMismatch,
    PacketTargetMismatch,
    PacketPortsMismatch,
    PacketOperationMismatch,
    TransactionIdMismatch,
    MessageTypeMismatch,
    PacketClientMacMismatch,
    ParameterRequestListMismatch,
    FlagsMismatch,
    MaxMessageSizeMismatch,
    ChecksumMissing,
    FrameLengthMismatch,
    CounterMismatch,
};

const VirtioNetDnsProbeError = VirtioNetProtocolInitError || error{
    TxFailed,
    RxTimedOut,
    LastFrameTooShort,
    LastFrameNotIpv4,
    LastIpv4DecodeFailed,
    LastPacketNotUdp,
    LastUdpDecodeFailed,
    LastPacketNotDns,
    LastDnsDecodeFailed,
    PacketMissing,
    PacketDestinationMismatch,
    PacketSourceMismatch,
    PacketProtocolMismatch,
    PacketSenderMismatch,
    PacketTargetMismatch,
    PacketPortsMismatch,
    TransactionIdMismatch,
    FlagsMismatch,
    QuestionCountMismatch,
    QuestionNameMismatch,
    QuestionTypeMismatch,
    QuestionClassMismatch,
    AnswerCountMismatch,
    AnswerNameMismatch,
    AnswerTypeMismatch,
    AnswerClassMismatch,
    AnswerTtlMismatch,
    AnswerDataMismatch,
    ChecksumMissing,
    FrameLengthMismatch,
    CounterMismatch,
};

const VirtioNetTcpProbeError = VirtioNetProtocolInitError || error{
    TxFailed,
    RxTimedOut,
    LastFrameTooShort,
    LastFrameNotIpv4,
    LastIpv4DecodeFailed,
    LastPacketNotTcp,
    LastTcpDecodeFailed,
    PacketMissing,
    PacketDestinationMismatch,
    PacketSourceMismatch,
    PacketProtocolMismatch,
    PacketSenderMismatch,
    PacketTargetMismatch,
    PacketPortsMismatch,
    PacketSequenceMismatch,
    PacketAcknowledgmentMismatch,
    PacketFlagsMismatch,
    WindowSizeMismatch,
    PayloadMismatch,
    FrameLengthMismatch,
    CounterMismatch,
    SessionStateMismatch,
};

const VirtioNetHttpPostProbeError = VirtioNetTcpProbeError || error{
    HttpPostFailed,
    HttpPostResponseMismatch,
};

const VirtioNetHttpsPostProbeError = VirtioNetTcpProbeError || error{
    HttpsPostFailed,
    HttpsPostResponseMismatch,
    HttpsPostNoTxProgress,
    HttpsPostNoRxProgress,
    HttpsPostTimeoutAfterRx,
    HttpsPostTlsAlert,
    HttpsPostTlsProtocolFailed,
    HttpsPostEntropyFailed,
    HttpsPostReadFailed,
    HttpsPostWriteFailed,
    HttpsPostTcpUnexpectedFlags,
    HttpsPostTcpSequenceMismatch,
    HttpsPostTcpAckMismatch,
    HttpsPostTcpWindowExceeded,
    HttpsPostTlsMessageTooLong,
    HttpsPostTlsTargetTooSmall,
    HttpsPostTlsBufferTooSmall,
    HttpsPostTlsNegativeIntoUnsigned,
    HttpsPostTlsInvalidSignature,
    HttpsPostTlsUnexpectedMessage,
    HttpsPostTlsIllegalParameter,
    HttpsPostTlsDecryptFailure,
    HttpsPostTlsRecordOverflow,
    HttpsPostTlsBadRecordMac,
    HttpsPostTlsDecryptError,
    HttpsPostTlsConnectionTruncated,
    HttpsPostTlsDecodeError,
    HttpsPostTlsAtServerHello,
    HttpsPostTlsAtEncryptedExtensions,
    HttpsPostTlsAtCertificate,
    HttpsPostTlsCertificateHostMismatch,
    HttpsPostTlsCertificateIssuerMismatch,
    HttpsPostTlsCertificateSignatureInvalid,
    HttpsPostTlsCertificateExpired,
    HttpsPostTlsCertificateNotYetValid,
    HttpsPostTlsCertificatePublicKeyInvalid,
    HttpsPostTlsCertificateTimeInvalid,
    HttpsPostTlsAtTrustChainEstablished,
    HttpsPostTlsAtCertificateVerify,
    HttpsPostTlsAtServerFinishedVerified,
    HttpsPostTlsBeforeClientFinished,
    HttpsPostTlsAfterClientFinished,
    HttpsPostTlsAfterInit,
    HttpsPostPreTlsNoSynEmit,
    HttpsPostPreTlsNoSynAck,
    HttpsPostTlsNoWriterFlush,
    HttpsPostTlsNoPayloadEmit,
    HttpsPostTlsWindowBlockedBeforeEmit,
    HttpsPostLastTxNotIpv4,
    HttpsPostLastTxIpv4DecodeFailed,
    HttpsPostLastTxNotTcp,
    HttpsPostLastTxTcpDecodeFailed,
    HttpsPostLastTxDestinationMismatch,
    HttpsPostLastTxPortsMismatch,
    HttpsPostLastTxFlagsMismatch,
};

const VirtioNetToolServiceProbeError = VirtioNetTcpProbeError || error{
    ToolServiceFailed,
    ToolServiceResponseMismatch,
};

const virtio_net_probe_remote_mac = [6]u8{ 0x02, 0x5A, 0x52, 0x10, 0x00, 0xF1 };
const virtio_net_probe_ethertype = [2]u8{ 0x88, 0xB7 };
const virtio_net_probe_receive_warmup_loops: usize = 8_000_000;
const e1000_probe_remote_mac = [6]u8{ 0x02, 0x5A, 0x52, 0x10, 0x00, 0xE1 };
const e1000_probe_ethertype = [2]u8{ 0x88, 0xB5 };
const e1000_probe_receive_warmup_loops: usize = 8_000_000;

const Rtl8139ArpProbeError = error{
    UnsupportedPlatform,
    DeviceNotFound,
    ResetTimeout,
    BufferProgramFailed,
    MacReadFailed,
        .e1000 => e1000.statePtr(),
        .virtio_net => virtio_net.statePtr(),
    };
}

pub export fn oc_ethernet_init() u8 {
    return switch (pal_net.currentBackend()) {
        .rtl8139 => if (rtl8139.init()) 1 else 0,
        .e1000 => if (e1000.init()) 1 else 0,
        .virtio_net => if (virtio_net.init()) 1 else 0,
    };
}

pub export fn oc_ethernet_reset() u8 {
    return switch (pal_net.currentBackend()) {
        .rtl8139 => blk: {
            rtl8139.resetForTest();
            break :blk if (rtl8139.init()) 1 else 0;
        },
        .e1000 => blk: {
            e1000.resetForTest();
            break :blk if (e1000.init()) 1 else 0;
        },
        .virtio_net => blk: {
            virtio_net.resetForTest();
            break :blk if (virtio_net.init()) 1 else 0;
        },
    };
}

pub export fn oc_ethernet_mac_byte(index: u32) u8 {
    return switch (pal_net.currentBackend()) {
        .rtl8139 => rtl8139.macByte(index),
        .e1000 => e1000.macByte(index),
        .virtio_net => virtio_net.macByte(index),
    };
}

pub export fn oc_ethernet_send_pattern(byte_len: u32, seed: u8) i16 {
    switch (pal_net.currentBackend()) {
        .rtl8139 => _ = rtl8139.sendPattern(byte_len, seed) catch return abi.result_not_supported,
        .e1000 => _ = e1000.sendPattern(byte_len, seed) catch return abi.result_not_supported,
        .virtio_net => _ = virtio_net.sendPattern(byte_len, seed) catch return abi.result_not_supported,
    }
    return abi.result_ok;
}

pub export fn oc_ethernet_poll() u32 {
    return switch (pal_net.currentBackend()) {
        .rtl8139 => rtl8139.pollReceive() catch 0,
        .e1000 => e1000.pollReceive() catch 0,
        .virtio_net => virtio_net.pollReceive() catch 0,
    };
}

pub export fn oc_ethernet_rx_byte(index: u32) u8 {
    return switch (pal_net.currentBackend()) {
        .rtl8139 => rtl8139.rxByte(index),
        .e1000 => e1000.rxByte(index),
        .virtio_net => virtio_net.rxByte(index),
    };
}

pub export fn oc_ethernet_rx_len() u32 {
    return oc_ethernet_state_ptr().last_rx_len;
}

pub export fn oc_ethernet_tx_byte(index: u32) u8 {
    return switch (pal_net.currentBackend()) {
        .rtl8139 => rtl8139.txByte(index),
        .e1000 => e1000.txByte(index),
        .virtio_net => virtio_net.txByte(index),
    };
}

pub export fn oc_storage_state_ptr() *const BaremetalStorageState {
    return storage_backend.statePtr();
}

pub export fn oc_storage_backend_count() u32 {
    storage_backend.init();
    return storage_backend.backendCount();
}

pub export fn oc_storage_backend_available(index: u32) u32 {
    if (index > std.math.maxInt(u8)) return 0;
    return if (storage_backend.isBackendAvailable(@as(u8, @intCast(index)))) 1 else 0;
}

pub export fn oc_storage_logical_base_lba() u32 {
    return storage_backend.logicalBaseLba();
}

pub export fn oc_storage_partition_count() u32 {
    return storage_backend.partitionCount();
}

pub export fn oc_storage_selected_partition_index() i16 {
    const index = storage_backend.selectedPartitionIndex() orelse return -1;
    return @as(i16, index);
}

pub export fn oc_storage_partition_info(index: u32) BaremetalStoragePartitionInfo {
    if (index > std.math.maxInt(u8)) {
        return std.mem.zeroes(BaremetalStoragePartitionInfo);
    }
    const info = storage_backend.partitionInfo(@as(u8, @intCast(index))) orelse {
        return std.mem.zeroes(BaremetalStoragePartitionInfo);
    };
    return .{
        .scheme = @intFromEnum(info.scheme),
        .reserved0 = .{ 0, 0, 0 },
        .start_lba = info.start_lba,
        .sector_count = info.sector_count,
    };
}

pub export fn oc_storage_init() void {
    storage_backend.init();
}

pub export fn oc_storage_reset() void {
    storage_backend.resetForTest();
    storage_backend.init();
}

pub export fn oc_storage_read_byte(lba: u32, offset: u32) u8 {
    return storage_backend.readByte(lba, offset);
}

pub export fn oc_storage_flush() i16 {
    if (e1000_probe_enabled) {
        runE1000Probe() catch |err| qemuExit(e1000ProbeFailureCode(err));
        qemuExit(qemu_e1000_probe_ok_code);
    }
    if (e1000_arp_probe_enabled) {
        runE1000ArpProbe() catch |err| qemuExit(e1000ArpProbeFailureCode(err));
        qemuExit(qemu_e1000_arp_probe_ok_code);
    }
    if (e1000_ipv4_probe_enabled) {
        runE1000Ipv4Probe() catch |err| qemuExit(e1000Ipv4ProbeFailureCode(err));
        qemuExit(qemu_e1000_ipv4_probe_ok_code);
    }
    if (e1000_udp_probe_enabled) {
        runE1000UdpProbe() catch |err| qemuExit(e1000UdpProbeFailureCode(err));
        qemuExit(qemu_e1000_udp_probe_ok_code);
    }
    if (e1000_tcp_probe_enabled) {
        runE1000TcpProbe() catch |err| qemuExit(e1000TcpProbeFailureCode(err));
        qemuExit(qemu_e1000_tcp_probe_ok_code);
    }
    if (e1000_dhcp_probe_enabled) {
        runE1000DhcpProbe() catch |err| qemuExit(e1000DhcpProbeFailureCode(err));
        qemuExit(qemu_e1000_dhcp_probe_ok_code);
    }
    if (e1000_dns_probe_enabled) {
        runE1000DnsProbe() catch |err| qemuExit(e1000DnsProbeFailureCode(err));
        qemuExit(qemu_e1000_dns_probe_ok_code);
    }
    if (e1000_http_post_probe_enabled) {
        runE1000HttpPostProbe() catch |err| qemuExit(e1000HttpPostFailureCode(err));
        qemuExit(qemu_e1000_http_post_probe_ok_code);
    }
    if (e1000_https_post_probe_enabled) {
        runE1000HttpsPostProbe() catch |err| qemuExit(e1000HttpsPostFailureCode(err));
        qemuExit(qemu_e1000_https_post_probe_ok_code);
    }
    if (e1000_tool_service_probe_enabled) {
        runE1000ToolServiceProbe() catch |err| qemuExit(e1000ToolServiceProbeFailureCode(err));
        qemuExit(qemu_e1000_tool_service_probe_ok_code);
    }
    if (e1000_full_stack_probe_enabled) {
        runE1000FullStackProbe() catch |err| qemuExit(e1000FullStackProbeFailureCode(err));
        qemuExit(qemu_e1000_full_stack_probe_ok_code);
    }
    if (rtl8139_probe_enabled) {
        runRtl8139Probe() catch |err| qemuExit(rtl8139ProbeFailureCode(err));
        qemuExit(qemu_rtl8139_probe_ok_code);
    }
    if (rtl8139_arp_probe_enabled) {
        runRtl8139ArpProbe() catch |err| qemuExit(rtl8139ArpProbeFailureCode(err));
        qemuExit(qemu_rtl8139_arp_probe_ok_code);
    }
    if (rtl8139_ipv4_probe_enabled) {
        runRtl8139Ipv4Probe() catch |err| qemuExit(rtl8139Ipv4ProbeFailureCode(err));
        qemuExit(qemu_rtl8139_ipv4_probe_ok_code);
    }
    if (rtl8139_udp_probe_enabled) {
        runRtl8139UdpProbe() catch |err| qemuExit(rtl8139UdpProbeFailureCode(err));
        qemuExit(qemu_rtl8139_udp_probe_ok_code);
    }
    if (rtl8139_tcp_probe_enabled) {
        runRtl8139TcpProbe() catch |err| qemuExit(rtl8139TcpProbeFailureCode(err));
        qemuExit(qemu_rtl8139_tcp_probe_ok_code);
    }
    if (rtl8139_dhcp_probe_enabled) {
        runRtl8139DhcpProbe() catch |err| qemuExit(rtl8139DhcpProbeFailureCode(err));
        qemuExit(qemu_rtl8139_dhcp_probe_ok_code);
    }
    if (rtl8139_dns_probe_enabled) {
        runRtl8139DnsProbe() catch |err| qemuExit(rtl8139DnsProbeFailureCode(err));
        qemuExit(qemu_rtl8139_dns_probe_ok_code);
    }
    if (rtl8139_http_post_probe_enabled) {
        runRtl8139HttpPostProbe() catch |err| qemuExit(rtl8139TcpProbeFailureCode(err));
        qemuExit(qemu_rtl8139_http_post_probe_ok_code);
    }
    if (rtl8139_https_post_probe_enabled) {
        runRtl8139HttpsPostProbe() catch |err| qemuExit(rtl8139TcpProbeFailureCode(err));
        qemuExit(qemu_rtl8139_https_post_probe_ok_code);
    }
    if (rtl8139_runtime_service_probe_enabled) {
        runRtl8139RuntimeServiceProbe() catch |err| qemuExit(rtl8139TcpProbeFailureCode(err));
        qemuExit(qemu_rtl8139_runtime_service_probe_ok_code);
    }
    if (tool_exec_probe_enabled) {
        runToolExecProbe() catch |err| qemuExit(toolExecProbeFailureCode(err));
        qemuExit(qemu_tool_exec_probe_ok_code);
    }
    if (tool_runtime_probe_enabled) {
        runToolRuntimeProbe() catch |err| qemuExit(toolRuntimeProbeFailureCode(err));
        qemuExit(qemu_tool_runtime_probe_ok_code);
    }
    if (rtl8139_gateway_probe_enabled) {
        runRtl8139GatewayProbe() catch |err| qemuExit(rtl8139GatewayProbeFailureCode(err));
        qemuExit(qemu_rtl8139_gateway_probe_ok_code);
    }
    ps2_input.init();
    tool_layout.init() catch unreachable;
    if (console_probe_banner_enabled) {
        vga_text_console.clear();
        vga_text_console.write("OK");
fn runE1000Probe() E1000ProbeError!void {
    e1000.initDetailed() catch |err| return switch (err) {
        error.UnsupportedPlatform => error.UnsupportedPlatform,
        error.DeviceNotFound => error.DeviceNotFound,
        error.MissingMmioBar => error.MissingMmioBar,
        error.MissingIoBar => error.MissingIoBar,
        error.ResetTimeout => error.ResetTimeout,
        error.AutoReadTimeout => error.AutoReadTimeout,
        error.EepromReadFailed => error.EepromReadFailed,
        error.EepromChecksumMismatch => error.EepromChecksumMismatch,
        error.MacReadFailed => error.MacReadFailed,
        error.RingProgramFailed => error.RingProgramFailed,
    };
    const eth = e1000.statePtr();
    if (eth.magic != abi.ethernet_magic) return error.StateMagicMismatch;
    if (eth.backend != abi.ethernet_backend_e1000) return error.BackendMismatch;
    if (eth.initialized == 0) return error.InitFlagMismatch;
    if (!builtin.is_test and eth.hardware_backed == 0) return error.HardwareBackedMismatch;
    if (eth.io_base == 0) return error.IoBaseMismatch;
    if (macBytesAreZeroForDriver(e1000.macByte)) return error.MacReadFailed;

    const expect_mock_echo = builtin.is_test or eth.hardware_backed == 0;
    const expected_len: u32 = 96;
    if (expect_mock_echo) {
        e1000.enableMacLoopbackForProbe() catch return error.LoopbackEnableFailed;
        _ = e1000.sendPattern(expected_len, 0x41) catch return error.TxFailed;
    } else {
        var warmup: usize = 0;
        while (warmup < e1000_probe_receive_warmup_loops) : (warmup += 1) {
            spinPause(1);
        }
        var guest_mac = [6]u8{ 0, 0, 0, 0, 0, 0 };
        var mac_index: usize = 0;
        while (mac_index < guest_mac.len) : (mac_index += 1) {
            guest_mac[mac_index] = e1000.macByte(@as(u32, @intCast(mac_index)));
        }
        var probe_frame = [_]u8{0} ** expected_len;
        buildE1000ProbeFrame(probe_frame[0..], e1000_probe_remote_mac, guest_mac, 0x41);
        e1000.sendFrame(probe_frame[0..]) catch return error.TxFailed;
    }

    var attempts: usize = 0;
    var observed_len: u32 = 0;
    while (attempts < 200_000) : (attempts += 1) {
        observed_len = e1000.pollReceive() catch return error.RxTimedOut;
        if (observed_len != 0) break;
        spinPause(1);
    }
    if (observed_len == 0) {
        const nic_status = e1000.debugStatus();
        const tx_head = e1000.debugTxHead();
        const tx_tail = e1000.debugTxTail();
        const rx_head = e1000.debugRxHead();
        _ = e1000.debugRxTail();
        if ((nic_status & 0x2) == 0) return error.LinkDropped;
        if (expect_mock_echo and !e1000.debugLoopbackEnabled()) return error.LoopbackDropped;
        if (eth.tx_packets != 0 and tx_head == tx_tail) {
            return if (rx_head != 0) error.RxHeadAdvancedNoFrame else error.TxCompletedNoRxProgress;
        }
        return error.RxTimedOut;
    }
    if (observed_len != expected_len) return error.RxLengthMismatch;

    var rx_index: u32 = 0;
    while (rx_index < 6) : (rx_index += 1) {
        if (e1000.rxByte(rx_index) != e1000.macByte(rx_index)) return error.RxPatternMismatch;
        const expected_source = if (expect_mock_echo)
            e1000.macByte(rx_index)
        else
            e1000_probe_remote_mac[@as(usize, @intCast(rx_index))];
        if (e1000.rxByte(6 + rx_index) != expected_source) {
            return error.RxPatternMismatch;
        }
    }
    if (e1000.rxByte(12) != e1000_probe_ethertype[0] or e1000.rxByte(13) != e1000_probe_ethertype[1]) {
        return error.RxPatternMismatch;
    }

    rx_index = 14;
    while (rx_index < expected_len) : (rx_index += 1) {
        const expected = 0x41 +% @as(u8, @truncate(rx_index - 14));
        if (e1000.rxByte(rx_index) != expected) return error.RxPatternMismatch;
    }

    if (eth.tx_packets == 0 or eth.rx_packets == 0 or eth.last_rx_len != expected_len) return error.CounterMismatch;
}

fn runVirtioNetProbe() VirtioNetProbeError!void {
    virtio_net.initDetailed() catch |err| return switch (err) {
        error.UnsupportedPlatform => error.UnsupportedPlatform,
        error.DeviceNotFound => error.DeviceNotFound,
        error.MissingVersion1 => error.MissingVersion1,
        error.MissingMacFeature => error.MissingMacFeature,
        error.FeaturesRejected => error.FeaturesRejected,
        error.QueueUnavailable => error.QueueUnavailable,
        error.QueueTooSmall => error.QueueTooSmall,
        error.QueueInitFailed => error.QueueInitFailed,
        error.MacReadFailed => error.MacReadFailed,
    };
    const eth = virtio_net.statePtr();
    if (eth.magic != abi.ethernet_magic) return error.StateMagicMismatch;
    if (eth.backend != abi.ethernet_backend_virtio_net) return error.BackendMismatch;
    if (eth.initialized == 0) return error.InitFlagMismatch;
    if (!builtin.is_test and eth.hardware_backed == 0) return error.HardwareBackedMismatch;
    if (eth.io_base == 0) return error.IoBaseMismatch;
    if (macBytesAreZeroForDriver(virtio_net.macByte)) return error.MacReadFailed;

    const expect_mock_echo = builtin.is_test or eth.hardware_backed == 0;
    const expected_len: u32 = 96;
    if (expect_mock_echo) {
        _ = virtio_net.sendPattern(expected_len, 0x41) catch return error.TxFailed;
    } else {
        var warmup: usize = 0;
        while (warmup < virtio_net_probe_receive_warmup_loops) : (warmup += 1) {
            spinPause(1);
        }
        var guest_mac = [6]u8{ 0, 0, 0, 0, 0, 0 };
        var mac_index: usize = 0;
        while (mac_index < guest_mac.len) : (mac_index += 1) {
            guest_mac[mac_index] = virtio_net.macByte(@as(u32, @intCast(mac_index)));
        }
        var probe_frame = [_]u8{0} ** expected_len;
        buildVirtioNetProbeFrame(probe_frame[0..], virtio_net_probe_remote_mac, guest_mac, 0x41);
        virtio_net.sendFrame(probe_frame[0..]) catch return error.TxFailed;
    }

    var attempts: usize = 0;
    var observed_len: u32 = 0;
    while (attempts < 200_000) : (attempts += 1) {
        observed_len = virtio_net.pollReceive() catch return error.RxTimedOut;
        if (observed_len != 0) break;
        spinPause(1);
    }
    if (observed_len == 0) return error.RxTimedOut;
    if (observed_len != expected_len) return error.RxLengthMismatch;

    var rx_index: u32 = 0;
    while (rx_index < 6) : (rx_index += 1) {
        if (virtio_net.rxByte(rx_index) != virtio_net.macByte(rx_index)) return error.RxPatternMismatch;
        const expected_source = if (expect_mock_echo)
            virtio_net.macByte(rx_index)
        else
            virtio_net_probe_remote_mac[@as(usize, @intCast(rx_index))];
        if (virtio_net.rxByte(6 + rx_index) != expected_source) return error.RxPatternMismatch;
    }
    if (virtio_net.rxByte(12) != virtio_net_probe_ethertype[0] or virtio_net.rxByte(13) != virtio_net_probe_ethertype[1]) {
        return error.RxPatternMismatch;
    }

    rx_index = 14;
    while (rx_index < expected_len) : (rx_index += 1) {
        const expected = 0x41 +% @as(u8, @truncate(rx_index - 14));
        if (virtio_net.rxByte(rx_index) != expected) return error.RxPatternMismatch;
    }

    if (eth.tx_packets == 0 or eth.rx_packets == 0 or eth.last_rx_len != expected_len) return error.CounterMismatch;
}

fn initVirtioNetProtocol() VirtioNetProtocolInitError!*const BaremetalEthernetState {
    pal_net.selectBackend(.virtio_net);

    virtio_net.initDetailed() catch |err| return switch (err) {
        error.UnsupportedPlatform => error.UnsupportedPlatform,
        error.DeviceNotFound => error.DeviceNotFound,
        error.MissingVersion1 => error.MissingVersion1,
        error.MissingMacFeature => error.MissingMacFeature,
        error.FeaturesRejected => error.FeaturesRejected,
        error.QueueUnavailable => error.QueueUnavailable,
        error.QueueTooSmall => error.QueueTooSmall,
        error.QueueInitFailed => error.QueueInitFailed,
        error.MacReadFailed => error.MacReadFailed,
    };

    const eth = virtio_net.statePtr();
    if (eth.magic != abi.ethernet_magic) return error.StateMagicMismatch;
    if (eth.backend != abi.ethernet_backend_virtio_net) return error.BackendMismatch;
    if (eth.initialized == 0) return error.InitFlagMismatch;
    if (!builtin.is_test and eth.hardware_backed == 0) return error.HardwareBackedMismatch;
    if (eth.io_base == 0) return error.IoBaseMismatch;
    return eth;
}

fn warmVirtioNetProbeTransport(expect_mock_echo: bool) void {
    if (expect_mock_echo) return;
    var warmup: usize = 0;
    while (warmup < virtio_net_probe_receive_warmup_loops) : (warmup += 1) {
        spinPause(1);
    }
}

fn runVirtioNetArpProbe() VirtioNetArpProbeError!void {
    setProbeInterruptsEnabled(false);
    const eth = try initVirtioNetProtocol();
    const expect_mock_echo = builtin.is_test or eth.hardware_backed == 0;
    warmVirtioNetProbeTransport(expect_mock_echo);

    pal_net.clearRouteState();
    defer pal_net.clearRouteState();
    const sender_ip = [4]u8{ 10, 0, 2, 15 };
    const target_ip = [4]u8{ 10, 0, 2, 2 };
    pal_net.configureIpv4Route(sender_ip, .{ 255, 255, 255, 0 }, null);
    if ((pal_net.sendArpRequest(sender_ip, target_ip) catch return error.TxFailed) != arp_protocol.frame_len) {
        return error.TxFailed;
    }

    var attempts: usize = 0;
    var packet_opt: ?pal_net.ArpPacket = null;
    while (attempts < 200_000) : (attempts += 1) {
        packet_opt = pal_net.pollArpPacket() catch return error.PacketMissing;
        if (packet_opt != null) break;
        spinPause(1);
    }
    const packet = packet_opt orelse return error.RxTimedOut;

    const expected_destination = if (expect_mock_echo) ethernet_protocol.broadcast_mac else eth.mac;
    const expected_source = if (expect_mock_echo) eth.mac else virtio_net_probe_remote_mac;
    if (!std.mem.eql(u8, expected_destination[0..], packet.ethernet_destination[0..])) return error.PacketDestinationMismatch;
    if (!std.mem.eql(u8, expected_source[0..], packet.ethernet_source[0..])) return error.PacketSourceMismatch;
    if (packet.operation != arp_protocol.operation_request) return error.PacketOperationMismatch;
    if (!std.mem.eql(u8, eth.mac[0..], packet.sender_mac[0..]) or !std.mem.eql(u8, sender_ip[0..], packet.sender_ip[0..])) {
        return error.PacketSenderMismatch;
    }
    if (!std.mem.eql(u8, target_ip[0..], packet.target_ip[0..]) or !std.mem.eql(u8, &[_]u8{ 0, 0, 0, 0, 0, 0 }, packet.target_mac[0..])) {
        return error.PacketTargetMismatch;
    }
    if (eth.tx_packets == 0 or eth.rx_packets == 0 or eth.last_rx_len < arp_protocol.frame_len) return error.CounterMismatch;
}

fn runVirtioNetIpv4Probe() VirtioNetIpv4ProbeError!void {
    const eth = try initVirtioNetProtocol();
    const expect_mock_echo = builtin.is_test or eth.hardware_backed == 0;
    warmVirtioNetProbeTransport(expect_mock_echo);

    const source_ip = [4]u8{ 192, 168, 56, 10 };
    const destination_ip = [4]u8{ 192, 168, 56, 1 };
    const payload = "PING";
    const expected_wire_len: u32 = ethernet_protocol.header_len + ipv4_protocol.header_len + payload.len;
    const expected_frame_len: u32 = @max(expected_wire_len, 60);
    if ((pal_net.sendIpv4Frame(ethernet_protocol.broadcast_mac, source_ip, destination_ip, ipv4_protocol.protocol_udp, payload) catch return error.TxFailed) != expected_wire_len) {
        return error.TxFailed;
    }

    var attempts: usize = 0;
    var packet_opt: ?pal_net.Ipv4Packet = null;
    while (attempts < 200_000) : (attempts += 1) {
        packet_opt = pal_net.pollIpv4PacketStrict() catch |err| return switch (err) {
            error.NotIpv4 => error.LastFrameNotIpv4,
            error.FrameTooShort, error.PacketTooShort => error.LastFrameTooShort,
            error.InvalidVersion, error.UnsupportedOptions, error.InvalidTotalLength, error.HeaderChecksumMismatch => error.LastIpv4DecodeFailed,
            else => error.PacketMissing,
        };
        if (packet_opt != null) break;
        spinPause(1);
    }
    const packet = packet_opt orelse return error.RxTimedOut;

    const expected_destination = if (expect_mock_echo) ethernet_protocol.broadcast_mac else eth.mac;
    const expected_source = if (expect_mock_echo) eth.mac else virtio_net_probe_remote_mac;
    if (!std.mem.eql(u8, expected_destination[0..], packet.ethernet_destination[0..])) return error.PacketDestinationMismatch;
    if (!std.mem.eql(u8, expected_source[0..], packet.ethernet_source[0..])) return error.PacketSourceMismatch;
    if (packet.header.protocol != ipv4_protocol.protocol_udp) return error.PacketProtocolMismatch;
    if (!std.mem.eql(u8, source_ip[0..], packet.header.source_ip[0..])) return error.PacketSenderMismatch;
    if (!std.mem.eql(u8, destination_ip[0..], packet.header.destination_ip[0..])) return error.PacketTargetMismatch;
    if (!std.mem.eql(u8, payload, packet.payload[0..packet.payload_len])) return error.PayloadMismatch;
    if (eth.last_rx_len != expected_frame_len) return error.FrameLengthMismatch;
    if (eth.tx_packets == 0 or eth.rx_packets == 0) return error.CounterMismatch;
}

fn runVirtioNetUdpProbe() VirtioNetUdpProbeError!void {
    const eth = try initVirtioNetProtocol();
    const expect_mock_echo = builtin.is_test or eth.hardware_backed == 0;
    warmVirtioNetProbeTransport(expect_mock_echo);

    const source_ip = [4]u8{ 192, 168, 56, 10 };
    const destination_ip = [4]u8{ 192, 168, 56, 1 };
    const source_port: u16 = 4321;
    const destination_port: u16 = 9001;
    const payload = "OPENCLAW-UDP";
    const expected_wire_len: u32 = ethernet_protocol.header_len + ipv4_protocol.header_len + udp_protocol.header_len + payload.len;
    const expected_frame_len: u32 = @max(expected_wire_len, 60);
    if ((pal_net.sendUdpPacket(ethernet_protocol.broadcast_mac, source_ip, destination_ip, source_port, destination_port, payload) catch return error.TxFailed) != expected_wire_len) {
        return error.TxFailed;
    }

    var attempts: usize = 0;
    var packet_received = false;
    var packet_storage: pal_net.UdpPacket = undefined;
    while (attempts < 200_000) : (attempts += 1) {
        packet_received = pal_net.pollUdpPacketStrictInto(&packet_storage) catch |err| return switch (err) {
            error.NotIpv4 => error.LastFrameNotIpv4,
            error.NotUdp => error.LastPacketNotUdp,
            error.FrameTooShort, error.PacketTooShort => error.LastFrameTooShort,
            error.InvalidVersion, error.UnsupportedOptions, error.InvalidTotalLength, error.HeaderChecksumMismatch => error.LastIpv4DecodeFailed,
            error.InvalidLength, error.ChecksumMismatch => error.LastUdpDecodeFailed,
            else => error.PacketMissing,
        };
        if (packet_received) break;
        spinPause(1);
    }
    if (!packet_received) return error.RxTimedOut;

    const packet = &packet_storage;
    const expected_destination = if (expect_mock_echo) ethernet_protocol.broadcast_mac else eth.mac;
    const expected_source = if (expect_mock_echo) eth.mac else virtio_net_probe_remote_mac;
    if (!std.mem.eql(u8, expected_destination[0..], packet.ethernet_destination[0..])) return error.PacketDestinationMismatch;
    if (!std.mem.eql(u8, expected_source[0..], packet.ethernet_source[0..])) return error.PacketSourceMismatch;
    if (packet.ipv4_header.protocol != ipv4_protocol.protocol_udp) return error.PacketProtocolMismatch;
    if (!std.mem.eql(u8, source_ip[0..], packet.ipv4_header.source_ip[0..])) return error.PacketSenderMismatch;
    if (!std.mem.eql(u8, destination_ip[0..], packet.ipv4_header.destination_ip[0..])) return error.PacketTargetMismatch;
    if (packet.source_port != source_port or packet.destination_port != destination_port) return error.PacketPortsMismatch;
    if (packet.checksum_value == 0) return error.ChecksumMissing;
    if (!std.mem.eql(u8, payload, packet.payload[0..packet.payload_len])) return error.PayloadMismatch;
    if (eth.last_rx_len != expected_frame_len) return error.FrameLengthMismatch;
    if (eth.tx_packets == 0 or eth.rx_packets == 0) return error.CounterMismatch;
}

fn classifyVirtioNetDhcpProbeTimeout(eth: *const BaremetalEthernetState) VirtioNetDhcpProbeError {
    if (eth.last_rx_len != 0) {
        var frame: [pal_net.max_frame_len]u8 = undefined;
        const copy_len = copyLastEthernetFrame(frame[0..]);
        if (copy_len < ethernet_protocol.header_len) return error.LastFrameTooShort;
        const eth_header = ethernet_protocol.Header.decode(frame[0..copy_len]) catch return error.LastFrameTooShort;
        if (eth_header.ether_type != ethernet_protocol.ethertype_ipv4) return error.LastFrameNotIpv4;
        const ipv4_packet = ipv4_protocol.decode(frame[ethernet_protocol.header_len..copy_len]) catch return error.LastIpv4DecodeFailed;
        if (ipv4_packet.header.protocol != ipv4_protocol.protocol_udp) return error.LastPacketNotUdp;
        const udp_packet = udp_protocol.decode(ipv4_packet.payload, ipv4_packet.header.source_ip, ipv4_packet.header.destination_ip) catch return error.LastUdpDecodeFailed;
        if (!(udp_packet.source_port == dhcp_protocol.client_port or udp_packet.destination_port == dhcp_protocol.client_port or udp_packet.source_port == dhcp_protocol.server_port or udp_packet.destination_port == dhcp_protocol.server_port)) {
            return error.LastPacketNotDhcp;
        }
        _ = dhcp_protocol.decode(udp_packet.payload) catch return error.LastDhcpDecodeFailed;
    }
    return error.RxTimedOut;
}

fn classifyVirtioNetDnsProbeTimeout(eth: *const BaremetalEthernetState) VirtioNetDnsProbeError {
    if (eth.last_rx_len != 0) {
        var frame: [pal_net.max_frame_len]u8 = undefined;
        const copy_len = copyLastEthernetFrame(frame[0..]);
        if (copy_len < ethernet_protocol.header_len) return error.LastFrameTooShort;
        const eth_header = ethernet_protocol.Header.decode(frame[0..copy_len]) catch return error.LastFrameTooShort;
        if (eth_header.ether_type != ethernet_protocol.ethertype_ipv4) return error.LastFrameNotIpv4;
        const ipv4_packet = ipv4_protocol.decode(frame[ethernet_protocol.header_len..copy_len]) catch return error.LastIpv4DecodeFailed;
        if (ipv4_packet.header.protocol != ipv4_protocol.protocol_udp) return error.LastPacketNotUdp;
        const udp_packet = udp_protocol.decode(ipv4_packet.payload, ipv4_packet.header.source_ip, ipv4_packet.header.destination_ip) catch return error.LastUdpDecodeFailed;
        if (!(udp_packet.source_port == dns_protocol.default_port or udp_packet.destination_port == dns_protocol.default_port)) {
            return error.LastPacketNotDns;
        }
        _ = dns_protocol.decode(udp_packet.payload) catch return error.LastDnsDecodeFailed;
    }
    return error.RxTimedOut;
}

fn classifyVirtioNetTcpProbeTimeout(eth: *const BaremetalEthernetState) VirtioNetTcpProbeError {
    if (eth.last_rx_len != 0) {
        var frame: [pal_net.max_frame_len]u8 = undefined;
        const copy_len = copyLastTransmittedEthernetFrame(frame[0..]);
        if (copy_len < ethernet_protocol.header_len) return error.LastFrameTooShort;
        const eth_header = ethernet_protocol.Header.decode(frame[0..copy_len]) catch return error.LastFrameTooShort;
        if (eth_header.ether_type != ethernet_protocol.ethertype_ipv4) return error.LastFrameNotIpv4;
        const ipv4_packet = ipv4_protocol.decode(frame[ethernet_protocol.header_len..copy_len]) catch return error.LastIpv4DecodeFailed;
        if (ipv4_packet.header.protocol != ipv4_protocol.protocol_tcp) return error.LastPacketNotTcp;
        _ = tcp_protocol.decode(ipv4_packet.payload, ipv4_packet.header.source_ip, ipv4_packet.header.destination_ip) catch return error.LastTcpDecodeFailed;
    }
    return error.RxTimedOut;
}

fn buildE1000ProbeFrame(frame: []u8, destination_mac: [6]u8, source_mac: [6]u8, seed: u8) void {
    std.mem.copyForwards(u8, frame[0..6], destination_mac[0..]);
    std.mem.copyForwards(u8, frame[6..12], source_mac[0..]);
    frame[12] = e1000_probe_ethertype[0];
    frame[13] = e1000_probe_ethertype[1];
    var index: usize = 14;
    while (index < frame.len) : (index += 1) {
        frame[index] = seed +% @as(u8, @truncate(index - 14));
    }
}

fn warmE1000ProbeTransport(expect_mock_echo: bool) void {
    if (expect_mock_echo) return;
    var warmup: usize = 0;
    while (warmup < e1000_probe_receive_warmup_loops) : (warmup += 1) {
        spinPause(1);
    }
}

    const nic_status = e1000.debugStatus();
    const tx_head = e1000.debugTxHead();
    const tx_tail = e1000.debugTxTail();
    const rx_head = e1000.debugRxHead();

    if ((nic_status & 0x2) == 0) return .LinkDropped;
    if (eth.tx_packets != 0 and tx_head == tx_tail) {
        return if (rx_head != 0) .RxHeadAdvancedNoFrame else .TxCompletedNoRxProgress;
    }
    return .RxTimedOut;
}

fn classifyE1000ArpProbeTimeout(eth: *const BaremetalEthernetState) E1000ArpProbeError {
fn classifyE1000Ipv4ProbeTimeout(eth: *const BaremetalEthernetState) E1000Ipv4ProbeError {
fn classifyE1000UdpProbeTimeout(eth: *const BaremetalEthernetState) E1000UdpProbeError {
fn classifyE1000DhcpProbeTimeout(eth: *const BaremetalEthernetState) E1000DhcpProbeError {
    if (eth.last_rx_len != 0) {
        var frame: [pal_net.max_frame_len]u8 = undefined;
        const copy_len = copyLastEthernetFrame(frame[0..]);
        if (copy_len < ethernet_protocol.header_len) return error.LastFrameTooShort;
        const eth_header = ethernet_protocol.Header.decode(frame[0..copy_len]) catch return error.LastFrameTooShort;
        if (eth_header.ether_type != ethernet_protocol.ethertype_ipv4) return error.LastFrameNotIpv4;
        const ipv4_packet = ipv4_protocol.decode(frame[ethernet_protocol.header_len..copy_len]) catch return error.LastIpv4DecodeFailed;
        if (ipv4_packet.header.protocol != ipv4_protocol.protocol_udp) return error.LastPacketNotUdp;
        const udp_packet = udp_protocol.decode(ipv4_packet.payload, ipv4_packet.header.source_ip, ipv4_packet.header.destination_ip) catch return error.LastUdpDecodeFailed;
        if (!((udp_packet.source_port == dhcp_protocol.client_port and udp_packet.destination_port == dhcp_protocol.server_port) or
            (udp_packet.source_port == dhcp_protocol.server_port and udp_packet.destination_port == dhcp_protocol.client_port)))
        {
            return error.LastPacketNotDhcp;
        }
        _ = dhcp_protocol.decode(udp_packet.payload) catch return error.LastDhcpDecodeFailed;
    }

fn classifyE1000DnsProbeTimeout(eth: *const BaremetalEthernetState) E1000DnsProbeError {
    if (eth.last_rx_len != 0) {
        var frame: [pal_net.max_frame_len]u8 = undefined;
        const copy_len = copyLastEthernetFrame(frame[0..]);
        if (copy_len < ethernet_protocol.header_len) return error.LastFrameTooShort;
        const eth_header = ethernet_protocol.Header.decode(frame[0..copy_len]) catch return error.LastFrameTooShort;
        if (eth_header.ether_type != ethernet_protocol.ethertype_ipv4) return error.LastFrameNotIpv4;
        const ipv4_packet = ipv4_protocol.decode(frame[ethernet_protocol.header_len..copy_len]) catch return error.LastIpv4DecodeFailed;
        if (ipv4_packet.header.protocol != ipv4_protocol.protocol_udp) return error.LastPacketNotUdp;
        const udp_packet = udp_protocol.decode(ipv4_packet.payload, ipv4_packet.header.source_ip, ipv4_packet.header.destination_ip) catch return error.LastUdpDecodeFailed;
        if (!(udp_packet.source_port == dns_protocol.default_port or udp_packet.destination_port == dns_protocol.default_port)) {
            return error.LastPacketNotDns;
        }
        _ = dns_protocol.decode(udp_packet.payload) catch return error.LastDnsDecodeFailed;
    }

fn classifyE1000TcpProbeTimeout(eth: *const BaremetalEthernetState) E1000TcpProbeError {
    if (eth.last_rx_len != 0) {
        var frame: [pal_net.max_frame_len]u8 = undefined;
        const copy_len = copyLastTransmittedEthernetFrame(frame[0..]);
        if (copy_len < ethernet_protocol.header_len) return error.LastFrameTooShort;
        const eth_header = ethernet_protocol.Header.decode(frame[0..copy_len]) catch return error.LastFrameTooShort;
        if (eth_header.ether_type != ethernet_protocol.ethertype_ipv4) return error.LastFrameNotIpv4;
        const ipv4_packet = ipv4_protocol.decode(frame[ethernet_protocol.header_len..copy_len]) catch return error.LastIpv4DecodeFailed;
        if (ipv4_packet.header.protocol != ipv4_protocol.protocol_tcp) return error.LastPacketNotTcp;
        _ = tcp_protocol.decode(ipv4_packet.payload, ipv4_packet.header.source_ip, ipv4_packet.header.destination_ip) catch return error.LastTcpDecodeFailed;
    }

fn classifyE1000HttpsProbeTimeout(eth: *const BaremetalEthernetState) E1000HttpsPostProbeError {
    if (eth.last_rx_len != 0) {
        var frame: [pal_net.max_frame_len]u8 = undefined;
        const copy_len = copyLastTransmittedEthernetFrame(frame[0..]);
        if (copy_len < ethernet_protocol.header_len) return error.LastFrameTooShort;
        const eth_header = ethernet_protocol.Header.decode(frame[0..copy_len]) catch return error.LastFrameTooShort;
        if (eth_header.ether_type != ethernet_protocol.ethertype_ipv4) return error.LastFrameNotIpv4;
        const ipv4_packet = ipv4_protocol.decode(frame[ethernet_protocol.header_len..copy_len]) catch return error.LastIpv4DecodeFailed;
        if (ipv4_packet.header.protocol != ipv4_protocol.protocol_tcp) return error.LastPacketNotTcp;
        _ = tcp_protocol.decode(ipv4_packet.payload, ipv4_packet.header.source_ip, ipv4_packet.header.destination_ip) catch return error.LastTcpDecodeFailed;
    }

fn pollE1000TcpProbePacket(eth: *const BaremetalEthernetState, result: *pal_net.TcpPacket) E1000TcpProbeError!void {
    var attempts: usize = 0;
    while (attempts < 200_000) : (attempts += 1) {
        if (pal_net.pollTcpPacketStrictInto(result)) |packet_received| {
            if (packet_received) return;
        } else |err| {
            return switch (err) {
                error.NotIpv4 => error.LastFrameNotIpv4,
                error.NotTcp => error.LastPacketNotTcp,
                error.FrameTooShort, error.PacketTooShort => error.LastFrameTooShort,
                error.InvalidVersion, error.UnsupportedOptions, error.InvalidTotalLength, error.HeaderChecksumMismatch => error.LastIpv4DecodeFailed,
                error.InvalidDataOffset, error.ChecksumMismatch => error.LastTcpDecodeFailed,
                else => error.PacketMissing,
            };
        }
        spinPause(1);
    }
    return classifyE1000TcpProbeTimeout(eth);
}

fn sendE1000TcpProbeSegment(
    source_ip: [4]u8,
    destination_ip: [4]u8,
    source_port: u16,
    destination_port: u16,
    outbound: tcp_protocol.Outbound,
) E1000TcpProbeError!u32 {
    const expected_wire_len: u32 = @as(u32, @intCast(ethernet_protocol.header_len + ipv4_protocol.header_len + tcp_protocol.header_len + outbound.payload.len));
    const sent = pal_net.sendTcpPacket(
        ethernet_protocol.broadcast_mac,
        source_ip,
        destination_ip,
        source_port,
        destination_port,
        outbound.sequence_number,
        outbound.acknowledgment_number,
        outbound.flags,
        outbound.window_size,
        outbound.payload,
    ) catch return error.TxFailed;
    if (sent != expected_wire_len) return error.TxFailed;
    return @max(expected_wire_len, 60);
}

fn expectE1000TcpProbePacket(
    packet: *const pal_net.TcpPacket,
    expected_source_mac: [ethernet_protocol.mac_len]u8,
    expected_source_ip: [4]u8,
    expected_destination_ip: [4]u8,
    expected_source_port: u16,
    expected_destination_port: u16,
    expected: tcp_protocol.Outbound,
) E1000TcpProbeError!void {
    if (!std.mem.eql(u8, ethernet_protocol.broadcast_mac[0..], packet.ethernet_destination[0..])) return error.PacketDestinationMismatch;
    if (!std.mem.eql(u8, expected_source_mac[0..], packet.ethernet_source[0..])) return error.PacketSourceMismatch;
    if (packet.ipv4_header.protocol != ipv4_protocol.protocol_tcp) return error.PacketProtocolMismatch;
    if (!std.mem.eql(u8, expected_source_ip[0..], packet.ipv4_header.source_ip[0..])) return error.PacketSenderMismatch;
    if (!std.mem.eql(u8, expected_destination_ip[0..], packet.ipv4_header.destination_ip[0..])) return error.PacketTargetMismatch;
    if (packet.source_port != expected_source_port or packet.destination_port != expected_destination_port) return error.PacketPortsMismatch;
    if (packet.sequence_number != expected.sequence_number) return error.PacketSequenceMismatch;
    if (packet.acknowledgment_number != expected.acknowledgment_number) return error.PacketAcknowledgmentMismatch;
    if (packet.flags != expected.flags) return error.PacketFlagsMismatch;
    if (packet.window_size != expected.window_size) return error.WindowSizeMismatch;
    if (!std.mem.eql(u8, expected.payload, packet.payload[0..packet.payload_len])) return error.PayloadMismatch;
}

fn establishE1000TcpProbeSession(
    eth: *const BaremetalEthernetState,
    scratch: *Rtl8139TcpProbeScratch,
    client: *tcp_protocol.Session,
    server: *tcp_protocol.Session,
    source_ip: [4]u8,
    destination_ip: [4]u8,
) E1000ToolServiceProbeError!void {
    _ = try sendE1000TcpProbeSegment(source_ip, destination_ip, client.local_port, client.remote_port, syn);
    try pollE1000TcpProbePacket(eth, &scratch.packet_storage);
    try expectE1000TcpProbePacket(&scratch.packet_storage, eth.mac, source_ip, destination_ip, client.local_port, client.remote_port, syn);

    _ = try sendE1000TcpProbeSegment(destination_ip, source_ip, server.local_port, server.remote_port, syn_ack);
    try pollE1000TcpProbePacket(eth, &scratch.packet_storage);
    try expectE1000TcpProbePacket(&scratch.packet_storage, eth.mac, destination_ip, source_ip, server.local_port, server.remote_port, syn_ack);

    _ = try sendE1000TcpProbeSegment(source_ip, destination_ip, client.local_port, client.remote_port, ack);
    try pollE1000TcpProbePacket(eth, &scratch.packet_storage);
    try expectE1000TcpProbePacket(&scratch.packet_storage, eth.mac, source_ip, destination_ip, client.local_port, client.remote_port, ack);
fn exchangeE1000TcpProbeServiceRequest(
    eth: *const BaremetalEthernetState,
    scratch: *Rtl8139TcpProbeScratch,
    client: *tcp_protocol.Session,
    server: *tcp_protocol.Session,
    source_ip: [4]u8,
    destination_ip: [4]u8,
    request: []const u8,
    query_limit: usize,
    payload_limit: usize,
    response_limit: usize,
) E1000ToolServiceProbeError![]const u8 {
    _ = try sendE1000TcpProbeSegment(source_ip, destination_ip, client.local_port, client.remote_port, request_payload);
    try pollE1000TcpProbePacket(eth, &scratch.packet_storage);
    try expectE1000TcpProbePacket(&scratch.packet_storage, eth.mac, source_ip, destination_ip, client.local_port, client.remote_port, request_payload);
        _ = try sendE1000TcpProbeSegment(destination_ip, source_ip, server.local_port, server.remote_port, reply);
        try pollE1000TcpProbePacket(eth, &scratch.packet_storage);
        try expectE1000TcpProbePacket(&scratch.packet_storage, eth.mac, destination_ip, source_ip, server.local_port, server.remote_port, reply);
        _ = try sendE1000TcpProbeSegment(source_ip, destination_ip, client.local_port, client.remote_port, ack);
        try pollE1000TcpProbePacket(eth, &scratch.packet_storage);
        try expectE1000TcpProbePacket(&scratch.packet_storage, eth.mac, source_ip, destination_ip, client.local_port, client.remote_port, ack);
fn e1000TcpProbeLoopbackHook(frame: []const u8) void {
    e1000.injectProbeReceive(frame);
}

fn runE1000ArpProbe() E1000ArpProbeError!void {
    setProbeInterruptsEnabled(false);
    pal_net.selectBackend(.e1000);

    e1000.initDetailed() catch |err| return switch (err) {
        error.UnsupportedPlatform => error.UnsupportedPlatform,
        error.DeviceNotFound => error.DeviceNotFound,
        error.MissingMmioBar => error.MissingMmioBar,
        error.MissingIoBar => error.MissingIoBar,
        error.ResetTimeout => error.ResetTimeout,
        error.AutoReadTimeout => error.AutoReadTimeout,
        error.EepromReadFailed => error.EepromReadFailed,
        error.EepromChecksumMismatch => error.EepromChecksumMismatch,
        error.MacReadFailed => error.MacReadFailed,
        error.RingProgramFailed => error.RingProgramFailed,
    };

    const eth = e1000.statePtr();
    if (eth.magic != abi.ethernet_magic) return error.StateMagicMismatch;
    if (eth.backend != abi.ethernet_backend_e1000) return error.BackendMismatch;
    if (eth.initialized == 0) return error.InitFlagMismatch;
    if (!builtin.is_test and eth.hardware_backed == 0) return error.HardwareBackedMismatch;
    if (eth.io_base == 0) return error.IoBaseMismatch;

    const expect_mock_echo = builtin.is_test or eth.hardware_backed == 0;
    warmE1000ProbeTransport(expect_mock_echo);

    pal_net.clearRouteState();
    defer pal_net.clearRouteState();
    const sender_ip = [4]u8{ 10, 0, 2, 15 };
    const target_ip = [4]u8{ 10, 0, 2, 2 };
    pal_net.configureIpv4Route(sender_ip, .{ 255, 255, 255, 0 }, null);
    if ((pal_net.sendArpRequest(sender_ip, target_ip) catch return error.TxFailed) != arp_protocol.frame_len) {
        return error.TxFailed;
    }

    var attempts: usize = 0;
    var packet_opt: ?pal_net.ArpPacket = null;
    while (attempts < 200_000) : (attempts += 1) {
        packet_opt = pal_net.pollArpPacket() catch return error.PacketMissing;
        if (packet_opt != null) break;
        spinPause(1);
    }
    const packet = packet_opt orelse return classifyE1000ArpProbeTimeout(eth);

    const expected_destination = if (expect_mock_echo) ethernet_protocol.broadcast_mac else eth.mac;
    const expected_source = if (expect_mock_echo) eth.mac else e1000_probe_remote_mac;
    if (!std.mem.eql(u8, expected_destination[0..], packet.ethernet_destination[0..])) return error.PacketDestinationMismatch;
    if (!std.mem.eql(u8, expected_source[0..], packet.ethernet_source[0..])) return error.PacketSourceMismatch;
    if (packet.operation != arp_protocol.operation_request) return error.PacketOperationMismatch;
    if (!std.mem.eql(u8, eth.mac[0..], packet.sender_mac[0..]) or !std.mem.eql(u8, sender_ip[0..], packet.sender_ip[0..])) {
        return error.PacketSenderMismatch;
    }
    if (!std.mem.eql(u8, target_ip[0..], packet.target_ip[0..]) or !std.mem.eql(u8, &[_]u8{ 0, 0, 0, 0, 0, 0 }, packet.target_mac[0..])) {
        return error.PacketTargetMismatch;
    }
    if (eth.tx_packets == 0 or eth.rx_packets == 0 or eth.last_rx_len < arp_protocol.frame_len) return error.CounterMismatch;
}

fn runE1000Ipv4Probe() E1000Ipv4ProbeError!void {
    pal_net.selectBackend(.e1000);

    e1000.initDetailed() catch |err| return switch (err) {
        error.UnsupportedPlatform => error.UnsupportedPlatform,
        error.DeviceNotFound => error.DeviceNotFound,
        error.MissingMmioBar => error.MissingMmioBar,
        error.MissingIoBar => error.MissingIoBar,
        error.ResetTimeout => error.ResetTimeout,
        error.AutoReadTimeout => error.AutoReadTimeout,
        error.EepromReadFailed => error.EepromReadFailed,
        error.EepromChecksumMismatch => error.EepromChecksumMismatch,
        error.MacReadFailed => error.MacReadFailed,
        error.RingProgramFailed => error.RingProgramFailed,
    };

    const eth = e1000.statePtr();
    if (eth.magic != abi.ethernet_magic) return error.StateMagicMismatch;
    if (eth.backend != abi.ethernet_backend_e1000) return error.BackendMismatch;
    if (eth.initialized == 0) return error.InitFlagMismatch;
    if (!builtin.is_test and eth.hardware_backed == 0) return error.HardwareBackedMismatch;
    if (eth.io_base == 0) return error.IoBaseMismatch;

    const expect_mock_echo = builtin.is_test or eth.hardware_backed == 0;
    warmE1000ProbeTransport(expect_mock_echo);

    const source_ip = [4]u8{ 192, 168, 56, 10 };
    const destination_ip = [4]u8{ 192, 168, 56, 1 };
    const payload = "PING";
    const expected_wire_len: u32 = ethernet_protocol.header_len + ipv4_protocol.header_len + payload.len;
    const expected_frame_len: u32 = @max(expected_wire_len, 60);
    if ((pal_net.sendIpv4Frame(ethernet_protocol.broadcast_mac, source_ip, destination_ip, ipv4_protocol.protocol_udp, payload) catch return error.TxFailed) != expected_wire_len) {
        return error.TxFailed;
    }

    var attempts: usize = 0;
    var packet_opt: ?pal_net.Ipv4Packet = null;
    while (attempts < 200_000) : (attempts += 1) {
        packet_opt = pal_net.pollIpv4PacketStrict() catch |err| return switch (err) {
            error.NotIpv4 => error.LastFrameNotIpv4,
            error.FrameTooShort, error.PacketTooShort => error.LastFrameTooShort,
            error.InvalidVersion, error.UnsupportedOptions, error.InvalidTotalLength, error.HeaderChecksumMismatch => error.LastIpv4DecodeFailed,
            else => error.PacketMissing,
        };
        if (packet_opt != null) break;
        spinPause(1);
    }
    const packet = packet_opt orelse return classifyE1000Ipv4ProbeTimeout(eth);

    const expected_destination = if (expect_mock_echo) ethernet_protocol.broadcast_mac else eth.mac;
    const expected_source = if (expect_mock_echo) eth.mac else e1000_probe_remote_mac;
    if (!std.mem.eql(u8, expected_destination[0..], packet.ethernet_destination[0..])) return error.PacketDestinationMismatch;
    if (!std.mem.eql(u8, expected_source[0..], packet.ethernet_source[0..])) return error.PacketSourceMismatch;
    if (packet.header.protocol != ipv4_protocol.protocol_udp) return error.PacketProtocolMismatch;
    if (!std.mem.eql(u8, source_ip[0..], packet.header.source_ip[0..])) return error.PacketSenderMismatch;
    if (!std.mem.eql(u8, destination_ip[0..], packet.header.destination_ip[0..])) return error.PacketTargetMismatch;
    if (!std.mem.eql(u8, payload, packet.payload[0..packet.payload_len])) return error.PayloadMismatch;
    if (eth.last_rx_len != expected_frame_len) return error.FrameLengthMismatch;
    if (eth.tx_packets == 0 or eth.rx_packets == 0) return error.CounterMismatch;
}

fn runE1000UdpProbe() E1000UdpProbeError!void {
    pal_net.selectBackend(.e1000);

    e1000.initDetailed() catch |err| return switch (err) {
        error.UnsupportedPlatform => error.UnsupportedPlatform,
        error.DeviceNotFound => error.DeviceNotFound,
        error.MissingMmioBar => error.MissingMmioBar,
        error.MissingIoBar => error.MissingIoBar,
        error.ResetTimeout => error.ResetTimeout,
        error.AutoReadTimeout => error.AutoReadTimeout,
        error.EepromReadFailed => error.EepromReadFailed,
        error.EepromChecksumMismatch => error.EepromChecksumMismatch,
        error.MacReadFailed => error.MacReadFailed,
        error.RingProgramFailed => error.RingProgramFailed,
    };

    const eth = e1000.statePtr();
    if (eth.magic != abi.ethernet_magic) return error.StateMagicMismatch;
    if (eth.backend != abi.ethernet_backend_e1000) return error.BackendMismatch;
    if (eth.initialized == 0) return error.InitFlagMismatch;
    if (!builtin.is_test and eth.hardware_backed == 0) return error.HardwareBackedMismatch;
    if (eth.io_base == 0) return error.IoBaseMismatch;

    const expect_mock_echo = builtin.is_test or eth.hardware_backed == 0;
    warmE1000ProbeTransport(expect_mock_echo);

    const source_ip = [4]u8{ 192, 168, 56, 10 };
    const destination_ip = [4]u8{ 192, 168, 56, 1 };
    const source_port: u16 = 4321;
    const destination_port: u16 = 9001;
    const payload = "OPENCLAW-UDP";
    const expected_wire_len: u32 = ethernet_protocol.header_len + ipv4_protocol.header_len + udp_protocol.header_len + payload.len;
    const expected_frame_len: u32 = @max(expected_wire_len, 60);
    if ((pal_net.sendUdpPacket(ethernet_protocol.broadcast_mac, source_ip, destination_ip, source_port, destination_port, payload) catch return error.TxFailed) != expected_wire_len) {
        return error.TxFailed;
    }

    var attempts: usize = 0;
    var packet_received = false;
    var packet_storage: pal_net.UdpPacket = undefined;
    while (attempts < 200_000) : (attempts += 1) {
        packet_received = pal_net.pollUdpPacketStrictInto(&packet_storage) catch |err| return switch (err) {
            error.NotIpv4 => error.LastFrameNotIpv4,
            error.NotUdp => error.LastPacketNotUdp,
            error.FrameTooShort, error.PacketTooShort => error.LastFrameTooShort,
            error.InvalidVersion, error.UnsupportedOptions, error.InvalidTotalLength, error.HeaderChecksumMismatch => error.LastIpv4DecodeFailed,
            error.InvalidLength, error.ChecksumMismatch => error.LastUdpDecodeFailed,
            else => error.PacketMissing,
        };
        if (packet_received) break;
        spinPause(1);
    }
    if (!packet_received) return classifyE1000UdpProbeTimeout(eth);

    const packet = &packet_storage;
    const expected_destination = if (expect_mock_echo) ethernet_protocol.broadcast_mac else eth.mac;
    const expected_source = if (expect_mock_echo) eth.mac else e1000_probe_remote_mac;
    if (!std.mem.eql(u8, expected_destination[0..], packet.ethernet_destination[0..])) return error.PacketDestinationMismatch;
    if (!std.mem.eql(u8, expected_source[0..], packet.ethernet_source[0..])) return error.PacketSourceMismatch;
    if (packet.ipv4_header.protocol != ipv4_protocol.protocol_udp) return error.PacketProtocolMismatch;
    if (!std.mem.eql(u8, source_ip[0..], packet.ipv4_header.source_ip[0..])) return error.PacketSenderMismatch;
    if (!std.mem.eql(u8, destination_ip[0..], packet.ipv4_header.destination_ip[0..])) return error.PacketTargetMismatch;
    if (packet.source_port != source_port or packet.destination_port != destination_port) return error.PacketPortsMismatch;
    if (packet.checksum_value == 0) return error.ChecksumMissing;
    if (!std.mem.eql(u8, payload, packet.payload[0..packet.payload_len])) return error.PayloadMismatch;
    if (eth.last_rx_len != expected_frame_len) return error.FrameLengthMismatch;
    if (eth.tx_packets == 0 or eth.rx_packets == 0) return error.CounterMismatch;
}

fn runE1000DhcpProbe() E1000DhcpProbeError!void {
    setProbeInterruptsEnabled(false);
    pal_net.selectBackend(.e1000);

    e1000.initDetailed() catch |err| return switch (err) {
        error.UnsupportedPlatform => error.UnsupportedPlatform,
        error.DeviceNotFound => error.DeviceNotFound,
        error.MissingMmioBar => error.MissingMmioBar,
        error.MissingIoBar => error.MissingIoBar,
        error.ResetTimeout => error.ResetTimeout,
        error.AutoReadTimeout => error.AutoReadTimeout,
        error.EepromReadFailed => error.EepromReadFailed,
        error.EepromChecksumMismatch => error.EepromChecksumMismatch,
        error.MacReadFailed => error.MacReadFailed,
        error.RingProgramFailed => error.RingProgramFailed,
    };

    const eth = e1000.statePtr();
    if (eth.magic != abi.ethernet_magic) return error.StateMagicMismatch;
    if (eth.backend != abi.ethernet_backend_e1000) return error.BackendMismatch;
    if (eth.initialized == 0) return error.InitFlagMismatch;
    if (!builtin.is_test and eth.hardware_backed == 0) return error.HardwareBackedMismatch;
    if (eth.io_base == 0) return error.IoBaseMismatch;

    e1000.installProbeSendHook(e1000TcpProbeLoopbackHook);
    defer e1000.installProbeSendHook(null);

    warmE1000ProbeTransport(builtin.is_test or eth.hardware_backed == 0);

    const source_ip = if (builtin.is_test)
        [4]u8{ 0, 0, 0, 0 }
    else
        [4]u8{ 192, 168, 56, 10 };
    const destination_ip = if (builtin.is_test)
        [4]u8{ 255, 255, 255, 255 }
    else
        [4]u8{ 192, 168, 56, 1 };
    const source_port: u16 = if (builtin.is_test) dhcp_protocol.client_port else 4068;
    const destination_port: u16 = if (builtin.is_test) dhcp_protocol.server_port else 4067;
    const transaction_id: u32 = 0x1234_5678;
    const parameter_request_list = [_]u8{
        dhcp_protocol.option_subnet_mask,
        dhcp_protocol.option_router,
        dhcp_protocol.option_dns_server,
        dhcp_protocol.option_hostname,
    };
    var dhcp_payload: [pal_net.max_ipv4_payload_len]u8 = undefined;
    const dhcp_payload_len = dhcp_protocol.encodeDiscover(
        dhcp_payload[0..],
        eth.mac,
        transaction_id,
        parameter_request_list[0..],
    ) catch return error.TxFailed;
    const expected_wire_len = pal_net.sendUdpPacket(
        ethernet_protocol.broadcast_mac,
        source_ip,
        destination_ip,
        source_port,
        destination_port,
        dhcp_payload[0..dhcp_payload_len],
    ) catch return error.TxFailed;
    const expected_frame_len: u32 = @max(expected_wire_len, 60);

    var attempts: usize = 0;
    var packet_received = false;
    var packet_storage: pal_net.UdpPacket = undefined;
    while (attempts < 20_000) : (attempts += 1) {
        packet_received = pal_net.pollUdpPacketStrictInto(&packet_storage) catch |err| return switch (err) {
            error.NotIpv4 => error.LastFrameNotIpv4,
            error.FrameTooShort, error.PacketTooShort => error.LastFrameTooShort,
            error.InvalidVersion, error.UnsupportedOptions, error.InvalidTotalLength, error.HeaderChecksumMismatch => error.LastIpv4DecodeFailed,
            error.InvalidLength, error.ChecksumMismatch => error.LastUdpDecodeFailed,
            else => error.PacketMissing,
        };
        if (packet_received) break;
        spinPause(1);
    }

    if (!packet_received) return classifyE1000DhcpProbeTimeout(eth);
    const packet = &packet_storage;
    if (!std.mem.eql(u8, ethernet_protocol.broadcast_mac[0..], packet.ethernet_destination[0..])) return error.PacketDestinationMismatch;
    if (!std.mem.eql(u8, eth.mac[0..], packet.ethernet_source[0..])) return error.PacketSourceMismatch;
    if (packet.ipv4_header.protocol != ipv4_protocol.protocol_udp) return error.PacketProtocolMismatch;
    if (!std.mem.eql(u8, source_ip[0..], packet.ipv4_header.source_ip[0..])) return error.PacketSenderMismatch;
    if (!std.mem.eql(u8, destination_ip[0..], packet.ipv4_header.destination_ip[0..])) return error.PacketTargetMismatch;
    if (packet.source_port != source_port or packet.destination_port != destination_port) return error.PacketPortsMismatch;
    const decoded = dhcp_protocol.decode(packet.payload[0..packet.payload_len]) catch return error.LastDhcpDecodeFailed;
    if (decoded.op != dhcp_protocol.boot_request) return error.PacketOperationMismatch;
    if (decoded.transaction_id != transaction_id) return error.TransactionIdMismatch;
    if (decoded.message_type == null or decoded.message_type.? != dhcp_protocol.message_type_discover) return error.MessageTypeMismatch;
    if (!std.mem.eql(u8, eth.mac[0..], decoded.client_mac[0..])) return error.PacketClientMacMismatch;
    if (decoded.parameter_request_list.len != parameter_request_list.len or !std.mem.eql(u8, parameter_request_list[0..], decoded.parameter_request_list[0..])) {
        return error.ParameterRequestListMismatch;
    }
    if (decoded.flags != dhcp_protocol.flags_broadcast) return error.FlagsMismatch;
    if (decoded.client_identifier.len != 1 + ethernet_protocol.mac_len) return error.PacketClientMacMismatch;
    if (decoded.client_identifier[0] != dhcp_protocol.hardware_type_ethernet or !std.mem.eql(u8, eth.mac[0..], decoded.client_identifier[1 .. 1 + ethernet_protocol.mac_len])) {
        return error.PacketClientMacMismatch;
    }
    if (decoded.max_message_size == null or decoded.max_message_size.? != 1500) return error.MaxMessageSizeMismatch;
    if (packet.checksum_value == 0) return error.ChecksumMissing;
    if (eth.last_rx_len != expected_frame_len) return error.FrameLengthMismatch;
    if (eth.tx_packets == 0 or eth.rx_packets == 0) return error.CounterMismatch;
}

fn runE1000DnsProbe() E1000DnsProbeError!void {
    setProbeInterruptsEnabled(false);
    pal_net.selectBackend(.e1000);

    e1000.initDetailed() catch |err| return switch (err) {
        error.UnsupportedPlatform => error.UnsupportedPlatform,
        error.DeviceNotFound => error.DeviceNotFound,
        error.MissingMmioBar => error.MissingMmioBar,
        error.MissingIoBar => error.MissingIoBar,
        error.ResetTimeout => error.ResetTimeout,
        error.AutoReadTimeout => error.AutoReadTimeout,
        error.EepromReadFailed => error.EepromReadFailed,
        error.EepromChecksumMismatch => error.EepromChecksumMismatch,
        error.MacReadFailed => error.MacReadFailed,
        error.RingProgramFailed => error.RingProgramFailed,
    };

    const eth = e1000.statePtr();
    if (eth.magic != abi.ethernet_magic) return error.StateMagicMismatch;
    if (eth.backend != abi.ethernet_backend_e1000) return error.BackendMismatch;
    if (eth.initialized == 0) return error.InitFlagMismatch;
    if (!builtin.is_test and eth.hardware_backed == 0) return error.HardwareBackedMismatch;
    if (eth.io_base == 0) return error.IoBaseMismatch;

    e1000.installProbeSendHook(e1000TcpProbeLoopbackHook);
    defer e1000.installProbeSendHook(null);

    warmE1000ProbeTransport(builtin.is_test or eth.hardware_backed == 0);

    const source_ip = [4]u8{ 192, 168, 56, 10 };
    const server_ip = [4]u8{ 192, 168, 56, 1 };
    const source_port: u16 = 53000;
    const query_id: u16 = 0x1234;
    const query_name = "openclaw.local";
    const resolved_address = [4]u8{ 192, 168, 56, 1 };
    const response_destination_mac = if (builtin.is_test) eth.mac else ethernet_protocol.broadcast_mac;

    const expected_query_wire_len = pal_net.sendDnsQuery(
        ethernet_protocol.broadcast_mac,
        source_ip,
        server_ip,
        source_port,
        query_id,
        query_name,
        dns_protocol.type_a,
    ) catch return error.TxFailed;
    const expected_query_frame_len: u32 = @max(expected_query_wire_len, 60);

    var attempts: usize = 0;
    var packet_received = false;
    var query_packet_storage: pal_net.DnsPacket = undefined;
    while (attempts < 20_000) : (attempts += 1) {
        packet_received = pal_net.pollDnsPacketStrictInto(&query_packet_storage) catch |err| return switch (err) {
            error.NotIpv4 => error.LastFrameNotIpv4,
            error.NotUdp => error.LastPacketNotUdp,
            error.NotDns => error.LastPacketNotDns,
            error.FrameTooShort, error.PacketTooShort => error.LastFrameTooShort,
            error.InvalidVersion, error.UnsupportedOptions, error.InvalidTotalLength, error.HeaderChecksumMismatch => error.LastIpv4DecodeFailed,
            error.InvalidLength, error.ChecksumMismatch => error.LastUdpDecodeFailed,
            error.InvalidLabelLength, error.InvalidPointer, error.UnsupportedLabelType, error.NameTooLong, error.CompressionLoop, error.UnsupportedQuestionCount, error.ResourceDataTooLarge => error.LastDnsDecodeFailed,
            else => error.PacketMissing,
        };
        if (packet_received) break;
        spinPause(1);
    }

    if (!packet_received) return classifyE1000DnsProbeTimeout(eth);
    const query_packet = &query_packet_storage;
    if (!std.mem.eql(u8, ethernet_protocol.broadcast_mac[0..], query_packet.ethernet_destination[0..])) return error.PacketDestinationMismatch;
    if (!std.mem.eql(u8, eth.mac[0..], query_packet.ethernet_source[0..])) return error.PacketSourceMismatch;
    if (query_packet.ipv4_header.protocol != ipv4_protocol.protocol_udp) return error.PacketProtocolMismatch;
    if (!std.mem.eql(u8, source_ip[0..], query_packet.ipv4_header.source_ip[0..])) return error.PacketSenderMismatch;
    if (!std.mem.eql(u8, server_ip[0..], query_packet.ipv4_header.destination_ip[0..])) return error.PacketTargetMismatch;
    if (query_packet.source_port != source_port or query_packet.destination_port != dns_protocol.default_port) return error.PacketPortsMismatch;
    if (query_packet.id != query_id) return error.TransactionIdMismatch;
    if (query_packet.flags != dns_protocol.flags_standard_query) return error.FlagsMismatch;
    if (query_packet.question_count != 1) return error.QuestionCountMismatch;
    if (!std.mem.eql(u8, query_name, query_packet.question_name[0..query_packet.question_name_len])) return error.QuestionNameMismatch;
    if (query_packet.question_type != dns_protocol.type_a) return error.QuestionTypeMismatch;
    if (query_packet.question_class != dns_protocol.class_in) return error.QuestionClassMismatch;
    if (query_packet.answer_count != 0) return error.AnswerCountMismatch;
    if (query_packet.udp_checksum_value == 0) return error.ChecksumMissing;
    if (eth.last_rx_len != expected_query_frame_len) return error.FrameLengthMismatch;

    var response_payload: [pal_net.max_ipv4_payload_len]u8 = undefined;
    const response_payload_len = dns_protocol.encodeAResponse(
        response_payload[0..],
        query_id,
        query_name,
        300,
        resolved_address,
    ) catch return error.TxFailed;
    const expected_response_wire_len = pal_net.sendUdpPacket(
        response_destination_mac,
        server_ip,
        source_ip,
        dns_protocol.default_port,
        source_port,
        response_payload[0..response_payload_len],
    ) catch return error.TxFailed;
    const expected_response_frame_len: u32 = @max(expected_response_wire_len, 60);

    attempts = 0;
    packet_received = false;
    var response_packet_storage: pal_net.DnsPacket = undefined;
    while (attempts < 20_000) : (attempts += 1) {
        packet_received = pal_net.pollDnsPacketStrictInto(&response_packet_storage) catch |err| return switch (err) {
            error.NotIpv4 => error.LastFrameNotIpv4,
            error.NotUdp => error.LastPacketNotUdp,
            error.NotDns => error.LastPacketNotDns,
            error.FrameTooShort, error.PacketTooShort => error.LastFrameTooShort,
            error.InvalidVersion, error.UnsupportedOptions, error.InvalidTotalLength, error.HeaderChecksumMismatch => error.LastIpv4DecodeFailed,
            error.InvalidLength, error.ChecksumMismatch => error.LastUdpDecodeFailed,
            error.InvalidLabelLength, error.InvalidPointer, error.UnsupportedLabelType, error.NameTooLong, error.CompressionLoop, error.UnsupportedQuestionCount, error.ResourceDataTooLarge => error.LastDnsDecodeFailed,
            else => error.PacketMissing,
        };
        if (packet_received) break;
        spinPause(1);
    }

    if (!packet_received) return classifyE1000DnsProbeTimeout(eth);
    const response_packet = &response_packet_storage;
    if (!std.mem.eql(u8, response_destination_mac[0..], response_packet.ethernet_destination[0..])) return error.PacketDestinationMismatch;
    if (!std.mem.eql(u8, eth.mac[0..], response_packet.ethernet_source[0..])) return error.PacketSourceMismatch;
    if (response_packet.ipv4_header.protocol != ipv4_protocol.protocol_udp) return error.PacketProtocolMismatch;
    if (!std.mem.eql(u8, server_ip[0..], response_packet.ipv4_header.source_ip[0..])) return error.PacketSenderMismatch;
    if (!std.mem.eql(u8, source_ip[0..], response_packet.ipv4_header.destination_ip[0..])) return error.PacketTargetMismatch;
    if (response_packet.source_port != dns_protocol.default_port or response_packet.destination_port != source_port) return error.PacketPortsMismatch;
    if (response_packet.id != query_id) return error.TransactionIdMismatch;
    if (response_packet.flags != dns_protocol.flags_standard_success_response) return error.FlagsMismatch;
    if (response_packet.question_count != 1) return error.QuestionCountMismatch;
    if (!std.mem.eql(u8, query_name, response_packet.question_name[0..response_packet.question_name_len])) return error.QuestionNameMismatch;
    if (response_packet.question_type != dns_protocol.type_a) return error.QuestionTypeMismatch;
    if (response_packet.question_class != dns_protocol.class_in) return error.QuestionClassMismatch;
    if (response_packet.answer_count_total != 1 or response_packet.answer_count != 1) return error.AnswerCountMismatch;
    if (!std.mem.eql(u8, query_name, response_packet.answers[0].nameSlice())) return error.AnswerNameMismatch;
    if (response_packet.answers[0].rr_type != dns_protocol.type_a) return error.AnswerTypeMismatch;
    if (response_packet.answers[0].rr_class != dns_protocol.class_in) return error.AnswerClassMismatch;
    if (response_packet.answers[0].ttl != 300) return error.AnswerTtlMismatch;
    if (!std.mem.eql(u8, resolved_address[0..], response_packet.answers[0].dataSlice())) return error.AnswerDataMismatch;
    if (response_packet.udp_checksum_value == 0) return error.ChecksumMissing;
    if (eth.last_rx_len != expected_response_frame_len) return error.FrameLengthMismatch;
    if (eth.tx_packets < 2 or eth.rx_packets < 2) return error.CounterMismatch;
}

fn runE1000TcpProbe() E1000TcpProbeError!void {
    setProbeInterruptsEnabled(false);
    pal_net.selectBackend(.e1000);

    e1000.initDetailed() catch |err| return switch (err) {
        error.UnsupportedPlatform => error.UnsupportedPlatform,
        error.DeviceNotFound => error.DeviceNotFound,
        error.MissingMmioBar => error.MissingMmioBar,
        error.MissingIoBar => error.MissingIoBar,
        error.ResetTimeout => error.ResetTimeout,
        error.AutoReadTimeout => error.AutoReadTimeout,
        error.EepromReadFailed => error.EepromReadFailed,
        error.EepromChecksumMismatch => error.EepromChecksumMismatch,
        error.MacReadFailed => error.MacReadFailed,
        error.RingProgramFailed => error.RingProgramFailed,
    };

    const eth = e1000.statePtr();
    if (eth.magic != abi.ethernet_magic) return error.StateMagicMismatch;
    if (eth.backend != abi.ethernet_backend_e1000) return error.BackendMismatch;
    if (eth.initialized == 0) return error.InitFlagMismatch;
    if (!builtin.is_test and eth.hardware_backed == 0) return error.HardwareBackedMismatch;
    if (eth.io_base == 0) return error.IoBaseMismatch;

    e1000.installProbeSendHook(e1000TcpProbeLoopbackHook);
    defer e1000.installProbeSendHook(null);

    const source_ip = [4]u8{ 192, 168, 56, 10 };
    const destination_ip = [4]u8{ 192, 168, 56, 1 };
    const payload = "OPENCLAW-E1000-TCP";

    var packet_storage: pal_net.TcpPacket = undefined;
    var client = tcp_protocol.Session.initClient(4321, 443, 0x0102_0304, 4096);
    var server = tcp_protocol.Session.initServer(443, 4321, 0xA0B0_C0D0, 8192);

    const syn_frame_len = try sendE1000TcpProbeSegment(source_ip, destination_ip, client.local_port, client.remote_port, syn);
    try pollE1000TcpProbePacket(eth, &packet_storage);
    try expectE1000TcpProbePacket(&packet_storage, eth.mac, source_ip, destination_ip, client.local_port, client.remote_port, syn);
    if (eth.last_rx_len != syn_frame_len) return error.FrameLengthMismatch;

    const syn_ack_frame_len = try sendE1000TcpProbeSegment(destination_ip, source_ip, server.local_port, server.remote_port, syn_ack);
    try pollE1000TcpProbePacket(eth, &packet_storage);
    try expectE1000TcpProbePacket(&packet_storage, eth.mac, destination_ip, source_ip, server.local_port, server.remote_port, syn_ack);
    if (eth.last_rx_len != syn_ack_frame_len) return error.FrameLengthMismatch;

    const ack_frame_len = try sendE1000TcpProbeSegment(source_ip, destination_ip, client.local_port, client.remote_port, ack);
    try pollE1000TcpProbePacket(eth, &packet_storage);
    try expectE1000TcpProbePacket(&packet_storage, eth.mac, source_ip, destination_ip, client.local_port, client.remote_port, ack);
    if (eth.last_rx_len != ack_frame_len) return error.FrameLengthMismatch;
    const data_frame_len = try sendE1000TcpProbeSegment(source_ip, destination_ip, client.local_port, client.remote_port, data);
    try pollE1000TcpProbePacket(eth, &packet_storage);
    try expectE1000TcpProbePacket(&packet_storage, eth.mac, source_ip, destination_ip, client.local_port, client.remote_port, data);
    if (eth.last_rx_len != data_frame_len) return error.FrameLengthMismatch;
    const payload_ack_frame_len = try sendE1000TcpProbeSegment(destination_ip, source_ip, server.local_port, server.remote_port, payload_ack);
    try pollE1000TcpProbePacket(eth, &packet_storage);
    try expectE1000TcpProbePacket(&packet_storage, eth.mac, destination_ip, source_ip, server.local_port, server.remote_port, payload_ack);
    if (eth.last_rx_len != payload_ack_frame_len) return error.FrameLengthMismatch;
    const client_fin_frame_len = try sendE1000TcpProbeSegment(source_ip, destination_ip, client.local_port, client.remote_port, client_fin);
    try pollE1000TcpProbePacket(eth, &packet_storage);
    try expectE1000TcpProbePacket(&packet_storage, eth.mac, source_ip, destination_ip, client.local_port, client.remote_port, client_fin);
    if (eth.last_rx_len != client_fin_frame_len) return error.FrameLengthMismatch;
    const fin_ack_frame_len = try sendE1000TcpProbeSegment(destination_ip, source_ip, server.local_port, server.remote_port, fin_ack);
    try pollE1000TcpProbePacket(eth, &packet_storage);
    try expectE1000TcpProbePacket(&packet_storage, eth.mac, destination_ip, source_ip, server.local_port, server.remote_port, fin_ack);
    if (eth.last_rx_len != fin_ack_frame_len) return error.FrameLengthMismatch;
    const server_fin_frame_len = try sendE1000TcpProbeSegment(destination_ip, source_ip, server.local_port, server.remote_port, server_fin);
    try pollE1000TcpProbePacket(eth, &packet_storage);
    try expectE1000TcpProbePacket(&packet_storage, eth.mac, destination_ip, source_ip, server.local_port, server.remote_port, server_fin);
    if (eth.last_rx_len != server_fin_frame_len) return error.FrameLengthMismatch;
    const final_ack_frame_len = try sendE1000TcpProbeSegment(source_ip, destination_ip, client.local_port, client.remote_port, final_ack);
    try pollE1000TcpProbePacket(eth, &packet_storage);
    try expectE1000TcpProbePacket(&packet_storage, eth.mac, source_ip, destination_ip, client.local_port, client.remote_port, final_ack);
    if (eth.last_rx_len != final_ack_frame_len) return error.FrameLengthMismatch;
fn e1000ArpProbeFailureCode(err: E1000ArpProbeError) u8 {
    return switch (err) {
        error.UnsupportedPlatform => 0x46,
        error.DeviceNotFound => 0x47,
        error.MissingMmioBar => 0x48,
        error.MissingIoBar => 0x49,
        error.ResetTimeout => 0x4A,
        error.AutoReadTimeout => 0x4B,
        error.EepromReadFailed => 0x4C,
        error.EepromChecksumMismatch => 0x4D,
        error.MacReadFailed => 0x4E,
        error.RingProgramFailed => 0x4F,
        error.StateMagicMismatch => 0x50,
        error.BackendMismatch => 0x51,
        error.InitFlagMismatch => 0x52,
        error.HardwareBackedMismatch => 0x53,
        error.IoBaseMismatch => 0x54,
        error.TxFailed => 0x55,
        error.LinkDropped => 0x56,
        error.TxCompletedNoRxProgress => 0x57,
        error.RxHeadAdvancedNoFrame => 0x58,
        error.RxTimedOut => 0x59,
        error.PacketMissing => 0x5A,
        error.PacketDestinationMismatch => 0x5B,
        error.PacketSourceMismatch => 0x5C,
        error.PacketOperationMismatch => 0x5D,
        error.PacketSenderMismatch => 0x5E,
        error.PacketTargetMismatch => 0x5F,
        error.CounterMismatch => 0x60,
    };
}

fn e1000Ipv4ProbeFailureCode(err: E1000Ipv4ProbeError) u8 {
    return switch (err) {
        error.UnsupportedPlatform => 0x61,
        error.DeviceNotFound => 0x62,
        error.MissingMmioBar => 0x63,
        error.MissingIoBar => 0x64,
        error.ResetTimeout => 0x65,
        error.AutoReadTimeout => 0x66,
        error.EepromReadFailed => 0x67,
        error.EepromChecksumMismatch => 0x68,
        error.MacReadFailed => 0x69,
        error.RingProgramFailed => 0x6A,
        error.StateMagicMismatch => 0x6B,
        error.BackendMismatch => 0x6C,
        error.InitFlagMismatch => 0x6D,
        error.HardwareBackedMismatch => 0x6E,
        error.IoBaseMismatch => 0x6F,
        error.TxFailed => 0x70,
        error.LinkDropped => 0x71,
        error.TxCompletedNoRxProgress => 0x72,
        error.RxHeadAdvancedNoFrame => 0x73,
        error.RxTimedOut => 0x74,
        error.LastFrameTooShort => 0x75,
        error.LastFrameNotIpv4 => 0x76,
        error.LastIpv4DecodeFailed => 0x77,
        error.PacketMissing => 0x78,
        error.PacketDestinationMismatch => 0x79,
        error.PacketSourceMismatch => 0x7A,
        error.PacketProtocolMismatch => 0x7B,
        error.PacketSenderMismatch => 0x7C,
        error.PacketTargetMismatch => 0x7D,
        error.PayloadMismatch => 0x7E,
        error.FrameLengthMismatch => 0x7F,
        error.CounterMismatch => 0x80,
    };
}

fn e1000UdpProbeFailureCode(err: E1000UdpProbeError) u8 {
    return switch (err) {
        error.UnsupportedPlatform => 0x81,
        error.DeviceNotFound => 0x82,
        error.MissingMmioBar => 0x83,
        error.MissingIoBar => 0x84,
        error.ResetTimeout => 0x85,
        error.AutoReadTimeout => 0x86,
        error.EepromReadFailed => 0x87,
        error.EepromChecksumMismatch => 0x88,
        error.MacReadFailed => 0x89,
        error.RingProgramFailed => 0x8A,
        error.StateMagicMismatch => 0x8B,
        error.BackendMismatch => 0x8C,
        error.InitFlagMismatch => 0x8D,
        error.HardwareBackedMismatch => 0x8E,
        error.IoBaseMismatch => 0x8F,
        error.TxFailed => 0x90,
        error.LinkDropped => 0x91,
        error.TxCompletedNoRxProgress => 0x92,
        error.RxHeadAdvancedNoFrame => 0x93,
        error.RxTimedOut => 0x94,
        error.LastFrameTooShort => 0x95,
        error.LastFrameNotIpv4 => 0x96,
        error.LastIpv4DecodeFailed => 0x97,
        error.LastPacketNotUdp => 0x98,
        error.LastUdpDecodeFailed => 0x99,
        error.PacketMissing => 0x9A,
        error.PacketDestinationMismatch => 0x9B,
        error.PacketSourceMismatch => 0x9C,
        error.PacketProtocolMismatch => 0x9D,
        error.PacketSenderMismatch => 0x9E,
        error.PacketTargetMismatch => 0x9F,
        error.PacketPortsMismatch => 0xA0,
        error.ChecksumMissing => 0xA1,
        error.PayloadMismatch => 0xA2,
        error.FrameLengthMismatch => 0xA3,
        error.CounterMismatch => 0xA4,
    };
}

fn e1000DhcpProbeFailureCode(err: E1000DhcpProbeError) u8 {
    return switch (err) {
        error.LastPacketNotDhcp => 0xD1,
        error.LastDhcpDecodeFailed => 0xD2,
        error.PacketOperationMismatch => 0xD3,
        error.TransactionIdMismatch => 0xD4,
        error.MessageTypeMismatch => 0xD5,
        error.PacketClientMacMismatch => 0xD6,
        error.ParameterRequestListMismatch => 0xD7,
        error.FlagsMismatch => 0xD8,
        error.MaxMessageSizeMismatch => 0xD9,
        else => e1000UdpProbeFailureCode(@errorCast(err)),
    };
}

fn e1000DnsProbeFailureCode(err: E1000DnsProbeError) u8 {
    return switch (err) {
        error.LastPacketNotDns => 0xDA,
        error.LastDnsDecodeFailed => 0xDB,
        error.TransactionIdMismatch => 0xDC,
        error.FlagsMismatch => 0xDD,
        error.QuestionCountMismatch => 0xDE,
        error.QuestionNameMismatch => 0xDF,
        error.QuestionTypeMismatch => 0xE0,
        error.QuestionClassMismatch => 0xE1,
        error.AnswerCountMismatch => 0xE2,
        error.AnswerNameMismatch => 0xE3,
        error.AnswerTypeMismatch => 0xE4,
        error.AnswerClassMismatch => 0xE5,
        error.AnswerTtlMismatch => 0xE6,
        error.AnswerDataMismatch => 0xE7,
        else => e1000UdpProbeFailureCode(@errorCast(err)),
    };
}

fn e1000TcpProbeFailureCode(err: E1000TcpProbeError) u8 {
    return switch (err) {
        error.UnsupportedPlatform => 0xA5,
        error.DeviceNotFound => 0xA6,
        error.MissingMmioBar => 0xA7,
        error.MissingIoBar => 0xA8,
        error.ResetTimeout => 0xA9,
        error.AutoReadTimeout => 0xAA,
        error.EepromReadFailed => 0xAB,
        error.EepromChecksumMismatch => 0xAC,
        error.MacReadFailed => 0xAD,
        error.RingProgramFailed => 0xAE,
        error.StateMagicMismatch => 0xAF,
        error.BackendMismatch => 0xB0,
        error.InitFlagMismatch => 0xB1,
        error.HardwareBackedMismatch => 0xB2,
        error.IoBaseMismatch => 0xB3,
        error.TxFailed => 0xB4,
        error.LinkDropped => 0xB5,
        error.TxCompletedNoRxProgress => 0xB6,
        error.RxHeadAdvancedNoFrame => 0xB7,
        error.RxTimedOut => 0xB8,
        error.LastFrameTooShort => 0xB9,
        error.LastFrameNotIpv4 => 0xBA,
        error.LastIpv4DecodeFailed => 0xBB,
        error.LastPacketNotTcp => 0xBC,
        error.LastTcpDecodeFailed => 0xBD,
        error.PacketMissing => 0xBE,
        error.PacketDestinationMismatch => 0xBF,
        error.PacketSourceMismatch => 0xC0,
        error.PacketProtocolMismatch => 0xC1,
        error.PacketSenderMismatch => 0xC2,
        error.PacketTargetMismatch => 0xC3,
        error.PacketPortsMismatch => 0xC4,
        error.PacketSequenceMismatch => 0xC5,
        error.PacketAcknowledgmentMismatch => 0xC6,
        error.PacketFlagsMismatch => 0xC7,
        error.WindowSizeMismatch => 0xC8,
        error.PayloadMismatch => 0xC9,
        error.FrameLengthMismatch => 0xCA,
        error.CounterMismatch => 0xCB,
        error.SessionStateMismatch => 0xCC,
    };
}

fn e1000ToolServiceProbeFailureCode(err: E1000ToolServiceProbeError) u8 {
    return switch (err) {
        error.ToolServiceFailed => 0x97,
        error.ToolServiceResponseMismatch => 0x98,
        else => e1000TcpProbeFailureCode(@errorCast(err)),
    };
}

fn e1000FullStackProbeFailureCode(err: E1000ToolServiceProbeError) u8 {
    return e1000ToolServiceProbeFailureCode(err);
}

fn e1000HttpPostFailureCode(err: E1000HttpPostProbeError) u8 {
    return switch (err) {
        error.HttpPostFailed => 0xCD,
        error.HttpPostResponseMismatch => 0xCE,
        else => e1000TcpProbeFailureCode(@errorCast(err)),
    };
}

fn e1000HttpsPostFailureCode(err: E1000HttpsPostProbeError) u8 {
    return switch (err) {
        error.HttpsPostFailed => 0xCF,
        error.HttpsPostResponseMismatch => 0xD0,
        error.HttpsPostNoTxProgress => 0xD1,
        error.HttpsPostNoRxProgress => 0xD2,
        error.HttpsPostTimeoutAfterRx => 0xD3,
        error.HttpsPostTlsAlert => 0xD4,
        error.HttpsPostTlsProtocolFailed => 0xD5,
        error.HttpsPostEntropyFailed => 0xD6,
        error.HttpsPostReadFailed => 0xD7,
        error.HttpsPostWriteFailed => 0xD8,
        error.HttpsPostTcpUnexpectedFlags => 0xD9,
        error.HttpsPostTcpSequenceMismatch => 0xDA,
        error.HttpsPostTcpAckMismatch => 0xDB,
        error.HttpsPostTcpWindowExceeded => 0xDC,
        error.HttpsPostTlsMessageTooLong => 0xDD,
        error.HttpsPostTlsTargetTooSmall => 0xDE,
        error.HttpsPostTlsBufferTooSmall => 0xDF,
        error.HttpsPostTlsNegativeIntoUnsigned => 0xE0,
        error.HttpsPostTlsInvalidSignature => 0xE1,
        error.HttpsPostTlsUnexpectedMessage => 0xE2,
        error.HttpsPostTlsIllegalParameter => 0xE3,
        error.HttpsPostTlsDecryptFailure => 0xE4,
        error.HttpsPostTlsRecordOverflow => 0xE5,
        error.HttpsPostTlsBadRecordMac => 0xE6,
        error.HttpsPostTlsDecryptError => 0xE7,
        error.HttpsPostTlsConnectionTruncated => 0xE8,
        error.HttpsPostTlsDecodeError => 0xE9,
        error.HttpsPostTlsAtServerHello => 0xEA,
        error.HttpsPostTlsAtEncryptedExtensions => 0xEB,
        error.HttpsPostTlsAtCertificate => 0xEC,
        error.HttpsPostTlsCertificateHostMismatch => 0xED,
        error.HttpsPostTlsCertificateIssuerMismatch => 0xEE,
        error.HttpsPostTlsCertificateSignatureInvalid => 0xEF,
        error.HttpsPostTlsCertificateExpired => 0xF0,
        error.HttpsPostTlsCertificateNotYetValid => 0xF1,
        error.HttpsPostTlsCertificatePublicKeyInvalid => 0xF2,
        error.HttpsPostTlsCertificateTimeInvalid => 0xF3,
        error.HttpsPostTlsAtTrustChainEstablished => 0xF4,
        error.HttpsPostTlsAtCertificateVerify => 0xF5,
        error.HttpsPostTlsAtServerFinishedVerified => 0xF6,
        error.HttpsPostTlsBeforeClientFinished => 0xF7,
        error.HttpsPostTlsAfterClientFinished => 0xF8,
        error.HttpsPostTlsAfterInit => 0xF9,
        error.HttpsPostPreTlsNoSynEmit => 0xFA,
        error.HttpsPostPreTlsNoSynAck => 0xFB,
        error.HttpsPostTlsNoWriterFlush => 0xFC,
        error.HttpsPostTlsNoPayloadEmit => 0xFD,
        error.HttpsPostTlsWindowBlockedBeforeEmit => 0xFE,
        error.HttpsPostLastTxNotIpv4 => 0x90,
        error.HttpsPostLastTxIpv4DecodeFailed => 0x91,
        error.HttpsPostLastTxNotTcp => 0x92,
        error.HttpsPostLastTxTcpDecodeFailed => 0x93,
        error.HttpsPostLastTxDestinationMismatch => 0x94,
        error.HttpsPostLastTxPortsMismatch => 0x95,
        error.HttpsPostLastTxFlagsMismatch => 0x96,
        else => e1000TcpProbeFailureCode(@errorCast(err)),
    };
}

fn runRtl8139Probe() Rtl8139ProbeError!void {
    rtl8139.initDetailed() catch |err| return switch (err) {
        error.UnsupportedPlatform => error.UnsupportedPlatform,
        error.DeviceNotFound => error.DeviceNotFound,
        error.ResetTimeout => error.ResetTimeout,
        error.BufferProgramFailed => error.BufferProgramFailed,
        error.MacReadFailed => error.MacReadFailed,
fn e1000ProbeFailureCode(err: E1000ProbeError) u8 {
    return switch (err) {
        error.UnsupportedPlatform => 0x90,
        error.DeviceNotFound => 0x91,
        error.MissingMmioBar => 0x92,
        error.MissingIoBar => 0x93,
        error.ResetTimeout => 0x94,
        error.AutoReadTimeout => 0x95,
        error.EepromReadFailed => 0x96,
        error.EepromChecksumMismatch => 0x97,
        error.MacReadFailed => 0x98,
        error.RingProgramFailed => 0x99,
        error.StateMagicMismatch => 0x9A,
        error.BackendMismatch => 0x9B,
        error.InitFlagMismatch => 0x9C,
        error.HardwareBackedMismatch => 0x9D,
        error.IoBaseMismatch => 0x9E,
        error.TxFailed => 0x9F,
        error.LoopbackEnableFailed => 0xA0,
        error.LinkDropped => 0xA1,
        error.LoopbackDropped => 0xA2,
        error.TxCompletedNoRxProgress => 0xA3,
        error.RxHeadAdvancedNoFrame => 0xA4,
        error.RxTimedOut => 0xA5,
        error.RxLengthMismatch => 0xA6,
        error.RxPatternMismatch => 0xA7,
        error.CounterMismatch => 0xA8,
    };
}

fn virtioNetProbeFailureCode(err: VirtioNetProbeError) u8 {
    return switch (err) {
        error.UnsupportedPlatform => 0xB0,
        error.DeviceNotFound => 0xB1,
        error.MissingVersion1 => 0xB2,
        error.MissingMacFeature => 0xB3,
        error.FeaturesRejected => 0xB4,
        error.QueueUnavailable => 0xB5,
        error.QueueTooSmall => 0xB6,
        error.QueueInitFailed => 0xB7,
        error.MacReadFailed => 0xB8,
        error.StateMagicMismatch => 0xB9,
        error.BackendMismatch => 0xBA,
        error.InitFlagMismatch => 0xBB,
        error.HardwareBackedMismatch => 0xBC,
        error.IoBaseMismatch => 0xBD,
        error.TxFailed => 0xBE,
        error.RxTimedOut => 0xBF,
        error.RxLengthMismatch => 0xC0,
        error.RxPatternMismatch => 0xC1,
        error.CounterMismatch => 0xC2,
    };
}

fn virtioNetArpProbeFailureCode(err: VirtioNetArpProbeError) u8 {
    return switch (err) {
        error.UnsupportedPlatform => 0xC3,
        error.DeviceNotFound => 0xC4,
        error.MissingVersion1 => 0xC5,
        error.MissingMacFeature => 0xC6,
        error.FeaturesRejected => 0xC7,
        error.QueueUnavailable => 0xC8,
        error.QueueTooSmall => 0xC9,
        error.QueueInitFailed => 0xCA,
        error.MacReadFailed => 0xCB,
        error.StateMagicMismatch => 0xCC,
        error.BackendMismatch => 0xCD,
        error.InitFlagMismatch => 0xCE,
        error.HardwareBackedMismatch => 0xCF,
        error.IoBaseMismatch => 0xD0,
        error.TxFailed => 0xD1,
        error.RxTimedOut => 0xD2,
        error.PacketMissing => 0xD3,
        error.PacketDestinationMismatch => 0xD4,
        error.PacketSourceMismatch => 0xD5,
        error.PacketOperationMismatch => 0xD6,
        error.PacketSenderMismatch => 0xD7,
        error.PacketTargetMismatch => 0xD8,
        error.CounterMismatch => 0xD9,
    };
}

fn virtioNetIpv4ProbeFailureCode(err: VirtioNetIpv4ProbeError) u8 {
    return switch (err) {
        error.UnsupportedPlatform => 0xDA,
        error.DeviceNotFound => 0xDB,
        error.MissingVersion1 => 0xDC,
        error.MissingMacFeature => 0xDD,
        error.FeaturesRejected => 0xDE,
        error.QueueUnavailable => 0xDF,
        error.QueueTooSmall => 0xE0,
        error.QueueInitFailed => 0xE1,
        error.MacReadFailed => 0xE2,
        error.StateMagicMismatch => 0xE3,
        error.BackendMismatch => 0xE4,
        error.InitFlagMismatch => 0xE5,
        error.HardwareBackedMismatch => 0xE6,
        error.IoBaseMismatch => 0xE7,
        error.TxFailed => 0xE8,
        error.RxTimedOut => 0xE9,
        error.LastFrameTooShort => 0xEA,
        error.LastFrameNotIpv4 => 0xEB,
        error.LastIpv4DecodeFailed => 0xEC,
        error.PacketMissing => 0xED,
        error.PacketDestinationMismatch => 0xEE,
        error.PacketSourceMismatch => 0xEF,
        error.PacketProtocolMismatch => 0xF0,
        error.PacketSenderMismatch => 0xF1,
        error.PacketTargetMismatch => 0xF2,
        error.PayloadMismatch => 0xF3,
        error.FrameLengthMismatch => 0xF4,
        error.CounterMismatch => 0xF5,
    };
}

fn virtioNetUdpProbeFailureCode(err: VirtioNetUdpProbeError) u8 {
    return switch (err) {
        error.UnsupportedPlatform => 0xF6,
        error.DeviceNotFound => 0xF7,
        error.MissingVersion1 => 0xF8,
        error.MissingMacFeature => 0xF9,
        error.FeaturesRejected => 0xFA,
        error.QueueUnavailable => 0xFB,
        error.QueueTooSmall => 0xFC,
        error.QueueInitFailed => 0xFD,
        error.MacReadFailed => 0xFE,
        error.StateMagicMismatch => 0xFF,
        error.BackendMismatch => 0x80,
        error.InitFlagMismatch => 0x81,
        error.HardwareBackedMismatch => 0x82,
        error.IoBaseMismatch => 0x83,
        error.TxFailed => 0x84,
        error.RxTimedOut => 0x85,
        error.LastFrameTooShort => 0x86,
        error.LastFrameNotIpv4 => 0x87,
        error.LastIpv4DecodeFailed => 0x88,
        error.LastPacketNotUdp => 0x89,
        error.LastUdpDecodeFailed => 0x8A,
        error.PacketMissing => 0x8B,
        error.PacketDestinationMismatch => 0x8C,
        error.PacketSourceMismatch => 0x8D,
        error.PacketProtocolMismatch => 0x8E,
        error.PacketSenderMismatch => 0x8F,
        error.PacketTargetMismatch => 0x90,
        error.PacketPortsMismatch => 0x91,
        error.ChecksumMissing => 0x92,
        error.PayloadMismatch => 0x93,
        error.FrameLengthMismatch => 0x94,
        error.CounterMismatch => 0x95,
    };
}

fn virtioNetDhcpProbeFailureCode(err: VirtioNetDhcpProbeError) u8 {
    return switch (err) {
        error.UnsupportedPlatform => 0x96,
        error.DeviceNotFound => 0x97,
        error.MissingVersion1 => 0x98,
        error.MissingMacFeature => 0x99,
        error.FeaturesRejected => 0x9A,
        error.QueueUnavailable => 0x9B,
        error.QueueTooSmall => 0x9C,
        error.QueueInitFailed => 0x9D,
        error.MacReadFailed => 0x9E,
        error.StateMagicMismatch => 0x9F,
        error.BackendMismatch => 0xA0,
        error.InitFlagMismatch => 0xA1,
        error.HardwareBackedMismatch => 0xA2,
        error.IoBaseMismatch => 0xA3,
        error.TxFailed => 0xA4,
        error.RxTimedOut => 0xA5,
        error.LastFrameTooShort => 0xA6,
        error.LastFrameNotIpv4 => 0xA7,
        error.LastIpv4DecodeFailed => 0xA8,
        error.LastPacketNotUdp => 0xA9,
        error.LastUdpDecodeFailed => 0xAA,
        error.LastPacketNotDhcp => 0xAB,
        error.LastDhcpDecodeFailed => 0xAC,
        error.PacketMissing => 0xAD,
        error.PacketDestinationMismatch => 0xAE,
        error.PacketSourceMismatch => 0xAF,
        error.PacketProtocolMismatch => 0xB0,
        error.PacketSenderMismatch => 0xB1,
        error.PacketTargetMismatch => 0xB2,
        error.PacketPortsMismatch => 0xB3,
        error.PacketOperationMismatch => 0xB4,
        error.TransactionIdMismatch => 0xB5,
        error.MessageTypeMismatch => 0xB6,
        error.PacketClientMacMismatch => 0xB7,
        error.ParameterRequestListMismatch => 0xB8,
        error.FlagsMismatch => 0xB9,
        error.MaxMessageSizeMismatch => 0xBA,
        error.ChecksumMissing => 0xBB,
        error.FrameLengthMismatch => 0xBC,
        error.CounterMismatch => 0xBD,
    };
}

fn virtioNetDnsProbeFailureCode(err: VirtioNetDnsProbeError) u8 {
    return switch (err) {
        error.UnsupportedPlatform => 0xBE,
        error.DeviceNotFound => 0xBF,
        error.MissingVersion1 => 0xC0,
        error.MissingMacFeature => 0xC1,
        error.FeaturesRejected => 0xC2,
        error.QueueUnavailable => 0xC3,
        error.QueueTooSmall => 0xC4,
        error.QueueInitFailed => 0xC5,
        error.MacReadFailed => 0xC6,
        error.StateMagicMismatch => 0xC7,
        error.BackendMismatch => 0xC8,
        error.InitFlagMismatch => 0xC9,
        error.HardwareBackedMismatch => 0xCA,
        error.IoBaseMismatch => 0xCB,
        error.TxFailed => 0xCC,
        error.RxTimedOut => 0xCD,
        error.LastFrameTooShort => 0xCE,
        error.LastFrameNotIpv4 => 0xCF,
        error.LastIpv4DecodeFailed => 0xD0,
        error.LastPacketNotUdp => 0xD1,
        error.LastUdpDecodeFailed => 0xD2,
        error.LastPacketNotDns => 0xD3,
        error.LastDnsDecodeFailed => 0xD4,
        error.PacketMissing => 0xD5,
        error.PacketDestinationMismatch => 0xD6,
        error.PacketSourceMismatch => 0xD7,
        error.PacketProtocolMismatch => 0xD8,
        error.PacketSenderMismatch => 0xD9,
        error.PacketTargetMismatch => 0xDA,
        error.PacketPortsMismatch => 0xDB,
        error.TransactionIdMismatch => 0xDC,
        error.FlagsMismatch => 0xDD,
        error.QuestionCountMismatch => 0xDE,
        error.QuestionNameMismatch => 0xDF,
        error.QuestionTypeMismatch => 0xE0,
        error.QuestionClassMismatch => 0xE1,
        error.AnswerCountMismatch => 0xE2,
        error.AnswerNameMismatch => 0xE3,
        error.AnswerTypeMismatch => 0xE4,
        error.AnswerClassMismatch => 0xE5,
        error.AnswerTtlMismatch => 0xE6,
        error.AnswerDataMismatch => 0xE7,
        error.ChecksumMissing => 0xE8,
        error.FrameLengthMismatch => 0xE9,
        error.CounterMismatch => 0xEA,
    };
}

fn virtioNetTcpProbeFailureCode(err: VirtioNetTcpProbeError) u8 {
    return switch (err) {
        error.UnsupportedPlatform => 0xEB,
        error.DeviceNotFound => 0xEC,
        error.MissingVersion1 => 0xED,
        error.MissingMacFeature => 0xEE,
        error.FeaturesRejected => 0xEF,
        error.QueueUnavailable => 0xF0,
        error.QueueTooSmall => 0xF1,
        error.QueueInitFailed => 0xF2,
        error.MacReadFailed => 0xF3,
        error.StateMagicMismatch => 0xF4,
        error.BackendMismatch => 0xF5,
        error.InitFlagMismatch => 0xF6,
        error.HardwareBackedMismatch => 0xF7,
        error.IoBaseMismatch => 0xF8,
        error.TxFailed => 0xF9,
        error.RxTimedOut => 0xFA,
        error.LastFrameTooShort => 0xFB,
        error.LastFrameNotIpv4 => 0xFC,
        error.LastIpv4DecodeFailed => 0xFD,
        error.LastPacketNotTcp => 0xFE,
        error.LastTcpDecodeFailed => 0xFF,
        error.PacketMissing => 0x80,
        error.PacketDestinationMismatch => 0x81,
        error.PacketSourceMismatch => 0x82,
        error.PacketProtocolMismatch => 0x83,
        error.PacketSenderMismatch => 0x84,
        error.PacketTargetMismatch => 0x85,
        error.PacketPortsMismatch => 0x86,
        error.PacketSequenceMismatch => 0x87,
        error.PacketAcknowledgmentMismatch => 0x88,
        error.PacketFlagsMismatch => 0x89,
        error.WindowSizeMismatch => 0x8A,
        error.PayloadMismatch => 0x8B,
        error.FrameLengthMismatch => 0x8C,
        error.CounterMismatch => 0x8D,
        error.SessionStateMismatch => 0x8E,
    };
}

fn virtioNetToolServiceProbeFailureCode(err: VirtioNetToolServiceProbeError) u8 {
    return switch (err) {
        error.ToolServiceFailed => 0x8F,
        error.ToolServiceResponseMismatch => 0x90,
        else => virtioNetTcpProbeFailureCode(@errorCast(err)),
    };
}

fn virtioNetHttpPostFailureCode(err: VirtioNetHttpPostProbeError) u8 {
    return switch (err) {
        error.HttpPostFailed => 0x91,
        error.HttpPostResponseMismatch => 0x92,
        else => virtioNetTcpProbeFailureCode(@errorCast(err)),
    };
}

fn virtioNetHttpsPostFailureCode(err: VirtioNetHttpsPostProbeError) u8 {
    return switch (err) {
        error.HttpsPostFailed => 0x93,
        error.HttpsPostResponseMismatch => 0x94,
        error.HttpsPostNoTxProgress => 0x95,
        error.HttpsPostNoRxProgress => 0x96,
        error.HttpsPostTimeoutAfterRx => 0x97,
        error.HttpsPostTlsAlert => 0x98,
        error.HttpsPostTlsProtocolFailed => 0x99,
        error.HttpsPostEntropyFailed => 0x9A,
        error.HttpsPostReadFailed => 0x9B,
        error.HttpsPostWriteFailed => 0x9C,
        error.HttpsPostTcpUnexpectedFlags => 0x9D,
        error.HttpsPostTcpSequenceMismatch => 0x9E,
        error.HttpsPostTcpAckMismatch => 0x9F,
        error.HttpsPostTcpWindowExceeded => 0xA0,
        error.HttpsPostTlsMessageTooLong => 0xA1,
        error.HttpsPostTlsTargetTooSmall => 0xA2,
        error.HttpsPostTlsBufferTooSmall => 0xA3,
        error.HttpsPostTlsNegativeIntoUnsigned => 0xA4,
        error.HttpsPostTlsInvalidSignature => 0xA5,
        error.HttpsPostTlsUnexpectedMessage => 0xA6,
        error.HttpsPostTlsIllegalParameter => 0xA7,
        error.HttpsPostTlsDecryptFailure => 0xA8,
        error.HttpsPostTlsRecordOverflow => 0xA9,
        error.HttpsPostTlsBadRecordMac => 0xAA,
        error.HttpsPostTlsDecryptError => 0xAB,
        error.HttpsPostTlsConnectionTruncated => 0xAC,
        error.HttpsPostTlsDecodeError => 0xAD,
        error.HttpsPostTlsAtServerHello => 0xAE,
        error.HttpsPostTlsAtEncryptedExtensions => 0xAF,
        error.HttpsPostTlsAtCertificate => 0xB0,
        error.HttpsPostTlsCertificateHostMismatch => 0xB1,
        error.HttpsPostTlsCertificateIssuerMismatch => 0xB2,
        error.HttpsPostTlsCertificateSignatureInvalid => 0xB3,
        error.HttpsPostTlsCertificateExpired => 0xB4,
        error.HttpsPostTlsCertificateNotYetValid => 0xB5,
        error.HttpsPostTlsCertificatePublicKeyInvalid => 0xB6,
        error.HttpsPostTlsCertificateTimeInvalid => 0xB7,
        error.HttpsPostTlsAtTrustChainEstablished => 0xB8,
        error.HttpsPostTlsAtCertificateVerify => 0xB9,
        error.HttpsPostTlsAtServerFinishedVerified => 0xBA,
        error.HttpsPostTlsBeforeClientFinished => 0xBB,
        error.HttpsPostTlsAfterClientFinished => 0xBC,
        error.HttpsPostTlsAfterInit => 0xBD,
        error.HttpsPostPreTlsNoSynEmit => 0xBE,
        error.HttpsPostPreTlsNoSynAck => 0xBF,
        error.HttpsPostTlsNoWriterFlush => 0xC0,
        error.HttpsPostTlsNoPayloadEmit => 0xC1,
        error.HttpsPostTlsWindowBlockedBeforeEmit => 0xC2,
        error.HttpsPostLastTxNotIpv4 => 0xC3,
        error.HttpsPostLastTxIpv4DecodeFailed => 0xC4,
        error.HttpsPostLastTxNotTcp => 0xC5,
        error.HttpsPostLastTxTcpDecodeFailed => 0xC6,
        error.HttpsPostLastTxDestinationMismatch => 0xC7,
        error.HttpsPostLastTxPortsMismatch => 0xC8,
        error.HttpsPostLastTxFlagsMismatch => 0xC9,
        else => virtioNetTcpProbeFailureCode(@errorCast(err)),
    };
}

fn runRtl8139ArpProbe() Rtl8139ArpProbeError!void {
    setProbeInterruptsEnabled(false);

    rtl8139.initDetailed() catch |err| return switch (err) {
        error.UnsupportedPlatform => error.UnsupportedPlatform,
        error.DeviceNotFound => error.DeviceNotFound,
        error.ResetTimeout => error.ResetTimeout,
        error.BufferProgramFailed => error.BufferProgramFailed,
        error.MacReadFailed => error.MacReadFailed,
fn classifyLastTransmittedE1000TcpProbeFrame(expected_destination_ip: [4]u8, expected_destination_port: u16) E1000HttpsPostProbeError {
    const tx_len = @as(usize, @intCast(oc_ethernet_state_ptr().last_tx_len));
    if (tx_len == 0) return error.HttpsPostNoTxProgress;

    var frame: [pal_net.max_frame_len]u8 = undefined;
    const copy_len = copyLastTransmittedEthernetFrame(frame[0..]);
    if (copy_len < ethernet_protocol.header_len) return error.HttpsPostLastTxNotIpv4;
    const eth_header = ethernet_protocol.Header.decode(frame[0..copy_len]) catch return error.HttpsPostLastTxNotIpv4;
    if (eth_header.ether_type != ethernet_protocol.ethertype_ipv4) return error.HttpsPostLastTxNotIpv4;
    const ipv4_packet = ipv4_protocol.decode(frame[ethernet_protocol.header_len..copy_len]) catch return error.HttpsPostLastTxIpv4DecodeFailed;
    if (ipv4_packet.header.protocol != ipv4_protocol.protocol_tcp) return error.HttpsPostLastTxNotTcp;
    const tcp_packet = tcp_protocol.decode(ipv4_packet.payload, ipv4_packet.header.source_ip, ipv4_packet.header.destination_ip) catch return error.HttpsPostLastTxTcpDecodeFailed;
    if (!std.mem.eql(u8, ipv4_packet.header.destination_ip[0..], expected_destination_ip[0..])) return error.HttpsPostLastTxDestinationMismatch;
    if (tcp_packet.destination_port != expected_destination_port) return error.HttpsPostLastTxPortsMismatch;
    if (tcp_packet.flags != tcp_protocol.flag_syn) return error.HttpsPostLastTxFlagsMismatch;
    return error.HttpsPostNoRxProgress;
}

    e1000,
    virtio_net,
};

const NicHttpPostHarness = struct {
    backend: HttpProbeBackend = .rtl8139,
    local_mac: [ethernet_protocol.mac_len]u8,
    server_mac: [ethernet_protocol.mac_len]u8 = .{ 0x02, 0x13, 0x37, 0x55, 0x80, 0x01 },
    dns_mac: [ethernet_protocol.mac_len]u8 = .{ 0x02, 0x13, 0x37, 0x55, 0x80, 0x53 },
    client_ip: [4]u8 = .{ 192, 168, 56, 10 },
    server_ip: [4]u8 = .{ 192, 168, 56, 1 },
    dns_ip: [4]u8 = .{ 192, 168, 56, 53 },
    host_name: []const u8 = "post.openclaw.local",
    path: []const u8 = "/fs55/live-post",
    url: []const u8 = "http://post.openclaw.local:8080/fs55/live-post",
    request_payload: []const u8 = "{\"probe\":\"live-http\"}",
    response_body: []const u8 = "{\"ok\":true,\"live\":\"post\"}",
    server_port: u16 = 8080,
    client_port: u16 = 0,
    server: tcp_protocol.Session = tcp_protocol.Session.initServer(8080, 0, 0xC0D0_E0F0, 512),
    request_storage: [1024]u8 = [_]u8{0} ** 1024,
    request_len: usize = 0,
    response_storage: [512]u8 = [_]u8{0} ** 512,
    response_len: usize = 0,
    dns_payload_storage: [pal_net.max_ipv4_payload_len]u8 = [_]u8{0} ** pal_net.max_ipv4_payload_len,
    dns_query_storage: dns_protocol.Packet = undefined,
    segment_storage: [pal_net.max_ipv4_payload_len]u8 = [_]u8{0} ** pal_net.max_ipv4_payload_len,
    frame_storage: [pal_net.max_frame_len]u8 = [_]u8{0} ** pal_net.max_frame_len,
    response_sent: bool = false,
    fin_sent: bool = false,
    request_validated: bool = false,
    failure: ?Rtl8139TcpProbeError = null,

    fn handleOutgoingFrame(self: *NicHttpPostHarness, frame: []const u8) void {
        self.handleOutgoingFrameImpl(frame) catch |err| {
            self.failure = err;
            if (!builtin.is_test) qemuExit(rtl8139TcpProbeFailureCode(err));
        };
    }

    fn handleOutgoingFrameImpl(self: *NicHttpPostHarness, frame: []const u8) Rtl8139TcpProbeError!void {
        if (self.failure != null) return;
        const eth = ethernet_protocol.Header.decode(frame) catch return;
        switch (eth.ether_type) {
            ethernet_protocol.ethertype_arp => {
                const packet = arp_protocol.decodeFrame(frame) catch return;
                if (packet.operation != arp_protocol.operation_request) return;
                if (std.mem.eql(u8, packet.target_ip[0..], self.server_ip[0..]) or
                    std.mem.eql(u8, packet.target_ip[0..], self.dns_ip[0..]))
                {
                    try self.injectArpReply(packet.target_ip, packet.sender_ip);
                }
            },
            ethernet_protocol.ethertype_ipv4 => {
                const ip_packet = ipv4_protocol.decode(frame[ethernet_protocol.header_len..]) catch return;
                switch (ip_packet.header.protocol) {
                    ipv4_protocol.protocol_udp => try self.handleUdp(ip_packet),
                    ipv4_protocol.protocol_tcp => try self.handleTcp(ip_packet),
                    else => {},
                }
            },
            else => {},
        }
    }

    fn handleUdp(self: *NicHttpPostHarness, ip_packet: ipv4_protocol.Packet) Rtl8139TcpProbeError!void {
        const packet = udp_protocol.decode(ip_packet.payload, ip_packet.header.source_ip, ip_packet.header.destination_ip) catch return;
        if (packet.destination_port != dns_protocol.default_port) return;
        if (!std.mem.eql(u8, ip_packet.header.destination_ip[0..], self.dns_ip[0..])) return;
        dns_protocol.decodeInto(packet.payload, &self.dns_query_storage) catch return;
        if (!std.mem.eql(u8, self.dns_query_storage.questionName(), self.host_name)) return;

        const response_len = dns_protocol.encodeAResponse(self.dns_payload_storage[0..], self.dns_query_storage.id, self.host_name, 60, self.server_ip) catch {
            return error.HttpPostFailed;
        };
        try self.injectUdp(self.dns_ip, self.client_ip, dns_protocol.default_port, packet.source_port, self.dns_payload_storage[0..response_len]);
    }

    fn handleTcp(self: *NicHttpPostHarness, ip_packet: ipv4_protocol.Packet) Rtl8139TcpProbeError!void {
        const packet = tcp_protocol.decode(ip_packet.payload, ip_packet.header.source_ip, ip_packet.header.destination_ip) catch return;
        if (!std.mem.eql(u8, ip_packet.header.destination_ip[0..], self.server_ip[0..])) return;
        if (packet.destination_port != self.server_port) return;

        if (packet.flags == tcp_protocol.flag_syn) {
            self.client_port = packet.source_port;
            self.server = tcp_protocol.Session.initServer(self.server_port, self.client_port, 0xC0D0_E0F0, 512);
            const syn_ack = self.server.acceptSyn(packet) catch return error.HttpPostFailed;
            try self.injectTcp(self.server_ip, self.client_ip, syn_ack);
            return;
        }

        if (packet.flags == tcp_protocol.flag_ack and packet.payload.len == 0) {
            if (self.server.state == .syn_received) {
                self.server.acceptAck(packet) catch return error.HttpPostFailed;
                return;
            }
            if (self.response_sent and !self.fin_sent) {
                self.server.acceptAck(packet) catch return error.HttpPostFailed;
                const fin = self.server.buildFin() catch return error.HttpPostFailed;
                self.fin_sent = true;
                try self.injectTcp(self.server_ip, self.client_ip, fin);
                return;
            }
            if (self.fin_sent) {
                self.server.acceptAck(packet) catch return error.HttpPostFailed;
                return;
            }
            return;
        }

        if ((packet.flags & tcp_protocol.flag_ack) != 0 and packet.payload.len != 0 and (packet.flags & ~(tcp_protocol.flag_ack | tcp_protocol.flag_psh)) == 0) {
            self.server.acceptPayload(packet) catch return error.HttpPostFailed;
            if (self.request_len + packet.payload.len > self.request_storage.len) return error.HttpPostResponseMismatch;
            std.mem.copyForwards(u8, self.request_storage[self.request_len .. self.request_len + packet.payload.len], packet.payload);
            self.request_len += packet.payload.len;

            if (!self.requestComplete()) {
                const ack = self.server.buildAck() catch return error.HttpPostFailed;
                try self.injectTcp(self.server_ip, self.client_ip, ack);
                return;
            }

            try self.prepareResponse();
            const response = self.server.buildPayload(self.response_storage[0..self.response_len]) catch return error.HttpPostFailed;
            self.response_sent = true;
            try self.injectTcp(self.server_ip, self.client_ip, response);
        }
    }

    fn requestComplete(self: *const NicHttpPostHarness) bool {
        const request = self.request_storage[0..self.request_len];
        const header_end = std.mem.indexOf(u8, request, "\r\n\r\n") orelse return false;
        if (!std.mem.startsWith(u8, request, "POST ")) return false;
        if (std.mem.indexOf(u8, request[0..header_end], "Content-Length: ")) |index| {
            const line = request[index + "Content-Length: ".len .. header_end];
            const line_end = std.mem.indexOf(u8, line, "\r\n") orelse return false;
            const content_length = std.fmt.parseUnsigned(usize, std.mem.trim(u8, line[0..line_end], " "), 10) catch return false;
            return request.len >= header_end + 4 + content_length;
        }
        return false;
    }

    fn prepareResponse(self: *NicHttpPostHarness) Rtl8139TcpProbeError!void {
        if (self.response_len != 0) return;
        const request = self.request_storage[0..self.request_len];
        if (std.mem.indexOf(u8, request, self.path) == null) return error.HttpPostResponseMismatch;
        if (std.mem.indexOf(u8, request, "Host: post.openclaw.local:8080\r\n") == null) return error.HttpPostResponseMismatch;
            .e1000 => e1000.injectProbeReceive(frame[0..frame_len]),
            .virtio_net => virtio_net.injectProbeReceive(frame[0..frame_len]),
        }
    }

    fn injectUdp(
        self: *NicHttpPostHarness,
        source_ip: [4]u8,
        destination_ip: [4]u8,
        source_port: u16,
        destination_port: u16,
        payload: []const u8,
    ) Rtl8139TcpProbeError!void {
        const segment_len = (udp_protocol.Header{
            .source_port = source_port,
            .destination_port = destination_port,
        }).encode(self.segment_storage[0..], payload, source_ip, destination_ip) catch return error.HttpPostFailed;
        try self.injectIpv4Frame(source_ip, destination_ip, ipv4_protocol.protocol_udp, self.segment_storage[0..segment_len]);
    }

    fn injectTcp(self: *NicHttpPostHarness, source_ip: [4]u8, destination_ip: [4]u8, outbound: tcp_protocol.Outbound) Rtl8139TcpProbeError!void {
        const segment_len = tcp_protocol.encodeOutboundSegment(self.server, outbound, self.segment_storage[0..], source_ip, destination_ip) catch {
            return error.HttpPostFailed;
        };
        try self.injectIpv4Frame(source_ip, destination_ip, ipv4_protocol.protocol_tcp, self.segment_storage[0..segment_len]);
    }

    fn injectIpv4Frame(
        self: *NicHttpPostHarness,
        source_ip: [4]u8,
        destination_ip: [4]u8,
        protocol: u8,
        payload: []const u8,
    ) Rtl8139TcpProbeError!void {
        const source_mac = self.peerMacForIp(source_ip) orelse return error.HttpPostFailed;
        _ = (ethernet_protocol.Header{
            .destination = self.local_mac,
            .source = source_mac,
            .ether_type = ethernet_protocol.ethertype_ipv4,
        }).encode(self.frame_storage[0..]) catch return error.HttpPostFailed;
        const ipv4_header_len = (ipv4_protocol.Header{
            .protocol = protocol,
            .source_ip = source_ip,
            .destination_ip = destination_ip,
        }).encode(self.frame_storage[ethernet_protocol.header_len..], payload.len) catch return error.HttpPostFailed;
        std.mem.copyForwards(u8, self.frame_storage[ethernet_protocol.header_len + ipv4_header_len ..][0..payload.len], payload);
        switch (self.backend) {
            .rtl8139 => rtl8139.injectProbeReceive(self.frame_storage[0 .. ethernet_protocol.header_len + ipv4_header_len + payload.len]),
            .e1000 => e1000.injectProbeReceive(self.frame_storage[0 .. ethernet_protocol.header_len + ipv4_header_len + payload.len]),
            .virtio_net => virtio_net.injectProbeReceive(self.frame_storage[0 .. ethernet_protocol.header_len + ipv4_header_len + payload.len]),
        }
    }

    fn peerMacForIp(self: *const NicHttpPostHarness, source_ip: [4]u8) ?[ethernet_protocol.mac_len]u8 {
        if (std.mem.eql(u8, source_ip[0..], self.server_ip[0..])) return self.server_mac;
        if (std.mem.eql(u8, source_ip[0..], self.dns_ip[0..])) return self.dns_mac;
        return null;
    }
};

var nic_http_post_harness_scratch: NicHttpPostHarness = undefined;
var nic_http_post_harness: ?*NicHttpPostHarness = null;

fn nicTcpHttpPostHook(frame: []const u8) void {
    if (nic_http_post_harness) |harness| {
        harness.handleOutgoingFrame(frame);
    }
}

fn discardMockSendHook(frame: []const u8) void {
    _ = frame;
}

fn runVirtioNetHttpPostProbe() VirtioNetHttpPostProbeError!void {
    setProbeInterruptsEnabled(false);
    const eth = try initVirtioNetProtocol();

    pal_net.clearRouteState();
    defer pal_net.clearRouteState();
    pal_net.configureIpv4Route(.{ 192, 168, 56, 10 }, .{ 255, 255, 255, 0 }, null);
    nic_http_post_harness_scratch = .{ .backend = .virtio_net, .local_mac = eth.mac };
    const http_harness = &nic_http_post_harness_scratch;
    pal_net.configureDnsServers(&.{http_harness.dns_ip});
    nic_http_post_harness = http_harness;
    virtio_net.installProbeSendHook(nicTcpHttpPostHook);
    virtio_net.testInstallMockSendHook(discardMockSendHook);
    defer {
        virtio_net.testInstallMockSendHook(null);
        virtio_net.installProbeSendHook(null);
        nic_http_post_harness = null;
    }

    const tx_packets_before_http = eth.tx_packets;
    const rx_packets_before_http = eth.rx_packets;
        "REQ 1 echo virtio-net-service-ok",
        256,
        256,
        256,
    );
    if (!std.mem.eql(u8, short_response, "RESP 1 22\nvirtio-net-service-ok\n")) return error.ToolServiceResponseMismatch;

    const exec_response = try exchangeVirtioNetTcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 2 EXEC echo virtio-net-service-ok",
        256,
        256,
        512,
    );
    if (!std.mem.startsWith(u8, exec_response, "RESP 2 ")) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, exec_response, "exit=0 stdout_len=22 stderr_len=0\nstdout:\nvirtio-net-service-ok\nstderr:\n") == null) {
        return error.ToolServiceResponseMismatch;
    }

    const help_response = try exchangeVirtioNetTcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 3 help",
        4096,
        256,
        4096,
    );
    if (!std.mem.startsWith(u8, help_response, "RESP 3 ")) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, help_response, "OpenClaw bare-metal builtins:") == null) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, help_response, "workspace-suite-release-channel-activate") == null) return error.ToolServiceResponseMismatch;
fn runE1000HttpPostProbe() E1000HttpPostProbeError!void {
    setProbeInterruptsEnabled(false);
    pal_net.selectBackend(.e1000);

    e1000.initDetailed() catch |err| return switch (err) {
        error.UnsupportedPlatform => error.UnsupportedPlatform,
        error.DeviceNotFound => error.DeviceNotFound,
        error.MissingMmioBar => error.MissingMmioBar,
        error.MissingIoBar => error.MissingIoBar,
        error.ResetTimeout => error.ResetTimeout,
        error.AutoReadTimeout => error.AutoReadTimeout,
        error.EepromReadFailed => error.EepromReadFailed,
        error.EepromChecksumMismatch => error.EepromChecksumMismatch,
        error.MacReadFailed => error.MacReadFailed,
        error.RingProgramFailed => error.RingProgramFailed,
    };

    const eth = e1000.statePtr();
    if (eth.magic != abi.ethernet_magic) return error.StateMagicMismatch;
    if (eth.backend != abi.ethernet_backend_e1000) return error.BackendMismatch;
    if (eth.initialized == 0) return error.InitFlagMismatch;
    if (!builtin.is_test and eth.hardware_backed == 0) return error.HardwareBackedMismatch;
    if (eth.io_base == 0) return error.IoBaseMismatch;
    pal_net.clearRouteState();
    defer pal_net.clearRouteState();
    pal_net.configureIpv4Route(.{ 192, 168, 56, 10 }, .{ 255, 255, 255, 0 }, null);
    nic_http_post_harness_scratch = .{ .backend = .e1000, .local_mac = eth.mac };
    const http_harness = &nic_http_post_harness_scratch;
    pal_net.configureDnsServers(&.{http_harness.dns_ip});
    nic_http_post_harness = http_harness;
    e1000.installProbeSendHook(nicTcpHttpPostHook);
    e1000.testInstallMockSendHook(discardMockSendHook);
    defer {
        e1000.testInstallMockSendHook(null);
        e1000.installProbeSendHook(null);
        nic_http_post_harness = null;
    }

    const tx_packets_before_http = eth.tx_packets;
    const rx_packets_before_http = eth.rx_packets;
fn runE1000HttpsPostProbe() E1000HttpsPostProbeError!void {
    setProbeInterruptsEnabled(false);
    pal_net.selectBackend(.e1000);

    e1000.initDetailed() catch |err| return switch (err) {
        error.UnsupportedPlatform => error.UnsupportedPlatform,
        error.DeviceNotFound => error.DeviceNotFound,
        error.MissingMmioBar => error.MissingMmioBar,
        error.MissingIoBar => error.MissingIoBar,
        error.ResetTimeout => error.ResetTimeout,
        error.AutoReadTimeout => error.AutoReadTimeout,
        error.EepromReadFailed => error.EepromReadFailed,
        error.EepromChecksumMismatch => error.EepromChecksumMismatch,
        error.MacReadFailed => error.MacReadFailed,
        error.RingProgramFailed => error.RingProgramFailed,
    };

    const eth = e1000.statePtr();
    if (eth.magic != abi.ethernet_magic) return error.StateMagicMismatch;
    if (eth.backend != abi.ethernet_backend_e1000) return error.BackendMismatch;
    if (eth.initialized == 0) return error.InitFlagMismatch;
    if (!builtin.is_test and eth.hardware_backed == 0) return error.HardwareBackedMismatch;
    if (eth.io_base == 0) return error.IoBaseMismatch;

    e1000.installProbeSendHook(e1000TcpProbeLoopbackHook);
    defer e1000.installProbeSendHook(null);

    warmE1000ProbeTransport(builtin.is_test or eth.hardware_backed == 0);

    pal_net.clearRouteState();
    defer pal_net.clearRouteState();
    pal_net.configureIpv4Route(.{ 10, 0, 2, 15 }, .{ 255, 255, 255, 0 }, null);
    trust_store.installBundle("fs55-root", pal_net.httpsProbeTrustAnchorDer(), 0) catch return error.HttpsPostFailed;
    trust_store.selectBundle("fs55-root", 0) catch return error.HttpsPostFailed;
                        const tx_err = classifyLastTransmittedE1000TcpProbeFrame(.{ 10, 0, 2, 2 }, 8443);
                        if (tx_err != error.HttpsPostNoTxProgress) return tx_err;
                        return error.HttpsPostPreTlsNoSynEmit;
                    },
                    .syn_sent => return error.HttpsPostPreTlsNoSynAck,
                    else => {},
                }
                return error.HttpsPostTlsNoWriterFlush;
            }
            if (tls_transport_debug.sent_segments == 0) {
                const effective_window = @min(tls_transport_debug.last_remote_window, tls_transport_debug.last_congestion_window);
                if (tls_transport_debug.wait_writable_calls != 0 and tls_transport_debug.last_bytes_in_flight >= effective_window) {
                    return error.HttpsPostTlsWindowBlockedBeforeEmit;
                }
                return error.HttpsPostTlsNoPayloadEmit;
            }
            if (eth.tx_packets <= tx_packets_before_http) return error.HttpsPostNoTxProgress;
            if (eth.rx_packets <= rx_packets_before_http) {
                return classifyLastTransmittedE1000TcpProbeFrame(.{ 10, 0, 2, 2 }, 8443);
            }
            const timeout_err = classifyE1000HttpsProbeTimeout(eth);
            switch (timeout_err) {
                error.LastFrameNotIpv4,
                error.LastPacketNotTcp,
                error.LastIpv4DecodeFailed,
                error.LastTcpDecodeFailed,
                => {
                    const tx_err = classifyLastTransmittedE1000TcpProbeFrame(.{ 10, 0, 2, 2 }, 8443);
                    if (tx_err != error.HttpsPostNoRxProgress) return tx_err;
                    return error.HttpsPostNoRxProgress;
                },
                else => return timeout_err,
            }
        }
        if (any_err == error.TlsAlert) return error.HttpsPostTlsAlert;
        if (any_err == error.InsufficientEntropy) return error.HttpsPostEntropyFailed;
        if (any_err == error.ReadFailed) return error.HttpsPostReadFailed;
        if (any_err == error.WriteFailed) return error.HttpsPostWriteFailed;
        if (any_err == error.UnexpectedFlags) return error.HttpsPostTcpUnexpectedFlags;
        if (any_err == error.SequenceMismatch) return error.HttpsPostTcpSequenceMismatch;
        if (any_err == error.AcknowledgmentMismatch) return error.HttpsPostTcpAckMismatch;
        if (any_err == error.WindowExceeded) return error.HttpsPostTcpWindowExceeded;
        if (any_err == error.MessageTooLong) return error.HttpsPostTlsMessageTooLong;
        if (any_err == error.TargetTooSmall) return error.HttpsPostTlsTargetTooSmall;
        if (any_err == error.BufferTooSmall) return error.HttpsPostTlsBufferTooSmall;
        if (any_err == error.NegativeIntoUnsigned) return error.HttpsPostTlsNegativeIntoUnsigned;
        if (any_err == error.InvalidSignature) return error.HttpsPostTlsInvalidSignature;
        if (any_err == error.TlsUnexpectedMessage) return error.HttpsPostTlsUnexpectedMessage;
        if (any_err == error.TlsIllegalParameter) return error.HttpsPostTlsIllegalParameter;
        if (any_err == error.TlsDecryptFailure) return error.HttpsPostTlsDecryptFailure;
        if (any_err == error.TlsRecordOverflow) return error.HttpsPostTlsRecordOverflow;
        if (any_err == error.TlsBadRecordMac) return error.HttpsPostTlsBadRecordMac;
        if (any_err == error.TlsDecryptError) return error.HttpsPostTlsDecryptError;
        if (any_err == error.TlsConnectionTruncated) return error.HttpsPostTlsConnectionTruncated;
        if (any_err == error.TlsDecodeError) return error.HttpsPostTlsDecodeError;
        if (tls_stage == .certificate_received) {
            if (tls_certificate_error) |cert_err| {
                switch (cert_err) {
                    error.CertificateHostMismatch => return error.HttpsPostTlsCertificateHostMismatch,
                    error.CertificateIssuerMismatch => return error.HttpsPostTlsCertificateIssuerMismatch,
                    error.CertificateSignatureInvalid,
                    error.CertificateSignatureInvalidLength,
                    error.SignatureVerificationFailed,
                    error.InvalidSignature,
                    => return error.HttpsPostTlsCertificateSignatureInvalid,
                    error.CertificateExpired => return error.HttpsPostTlsCertificateExpired,
                    error.CertificateNotYetValid => return error.HttpsPostTlsCertificateNotYetValid,
                    error.CertificatePublicKeyInvalid => return error.HttpsPostTlsCertificatePublicKeyInvalid,
                    error.CertificateTimeInvalid => return error.HttpsPostTlsCertificateTimeInvalid,
                    else => {},
                }
            }
        }
        switch (tls_stage) {
            .server_hello_received => return error.HttpsPostTlsAtServerHello,
            .encrypted_extensions_received => return error.HttpsPostTlsAtEncryptedExtensions,
            .certificate_received => return error.HttpsPostTlsAtCertificate,
            .trust_chain_established => return error.HttpsPostTlsAtTrustChainEstablished,
            .certificate_verify_received => return error.HttpsPostTlsAtCertificateVerify,
            .server_finished_verified => return error.HttpsPostTlsAtServerFinishedVerified,
            .client_finished_flushed => return error.HttpsPostTlsAfterClientFinished,
            .init_complete => return error.HttpsPostTlsAfterInit,
            else => {},
        }
        if (std.mem.startsWith(u8, err_name, "Tls") or
            std.mem.startsWith(u8, err_name, "Certificate"))
        {
            return error.HttpsPostTlsProtocolFailed;
        }
        return error.HttpsPostFailed;
    };
    if (https_response.status_code != 200 or
        !std.mem.eql(u8, https_response.body, "{\"ok\":true,\"transport\":\"https\"}"))
    {
        return error.HttpsPostResponseMismatch;
    }
    if (eth.tx_packets <= tx_packets_before_http or eth.rx_packets <= rx_packets_before_http) {
        return error.CounterMismatch;
    }
}

fn runE1000ToolServiceProbe() E1000ToolServiceProbeError!void {
    qemuDebugWrite("ETS0\n");
    setProbeInterruptsEnabled(false);
    pal_net.selectBackend(.e1000);

    e1000.initDetailed() catch |err| return switch (err) {
        error.UnsupportedPlatform => error.UnsupportedPlatform,
        error.DeviceNotFound => error.DeviceNotFound,
        error.MissingMmioBar => error.MissingMmioBar,
        error.MissingIoBar => error.MissingIoBar,
        error.ResetTimeout => error.ResetTimeout,
        error.AutoReadTimeout => error.AutoReadTimeout,
        error.EepromReadFailed => error.EepromReadFailed,
        error.EepromChecksumMismatch => error.EepromChecksumMismatch,
        error.MacReadFailed => error.MacReadFailed,
        error.RingProgramFailed => error.RingProgramFailed,
    };

    const eth = e1000.statePtr();
    if (eth.magic != abi.ethernet_magic) return error.StateMagicMismatch;
    if (eth.backend != abi.ethernet_backend_e1000) return error.BackendMismatch;
    if (eth.initialized == 0) return error.InitFlagMismatch;
    if (!builtin.is_test and eth.hardware_backed == 0) return error.HardwareBackedMismatch;
    if (eth.io_base == 0) return error.IoBaseMismatch;

    e1000.installProbeSendHook(e1000TcpProbeLoopbackHook);
    defer e1000.installProbeSendHook(null);

    qemuDebugWrite("ETS1\n");
    warmE1000ProbeTransport(builtin.is_test or eth.hardware_backed == 0);
    qemuDebugWrite("ETS2\n");

    const source_ip = [4]u8{ 192, 168, 56, 10 };
    const destination_ip = [4]u8{ 192, 168, 56, 1 };
    const script = "write-file /tools/out/data.txt tcp-service-persisted";
    const put_request = std.fmt.bufPrint(&rtl8139_tcp_probe_scratch.service_request_put_buffer, "REQ 21 PUT /tools/scripts/net.oc {d}\n{s}", .{
        script.len,
        script,
    }) catch return error.ToolServiceFailed;

    var client = tcp_protocol.Session.initClient(4333, 445, 0x6162_6364, 4096);
    var server = tcp_protocol.Session.initServer(445, 4333, 0xA1B2_C3D4, 4096);
    const scratch = &rtl8139_tcp_probe_scratch;
    const tx_packets_before = eth.tx_packets;
    const rx_packets_before = eth.rx_packets;

    try establishE1000TcpProbeSession(eth, scratch, &client, &server, source_ip, destination_ip);
    qemuDebugWrite("ETS3\n");

    const short_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 1 echo e1000-service-ok",
        256,
        256,
        256,
    );
    if (!std.mem.eql(u8, short_response, "RESP 1 17\ne1000-service-ok\n")) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS4\n");

    const exec_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 2 EXEC echo e1000-service-ok",
        256,
        256,
        512,
    );
    if (!std.mem.startsWith(u8, exec_response, "RESP 2 ")) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, exec_response, "exit=0 stdout_len=17 stderr_len=0\nstdout:\ne1000-service-ok\nstderr:\n") == null) {
        return error.ToolServiceResponseMismatch;
    }
    qemuDebugWrite("ETS5\n");

    const help_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 3 help",
        4096,
        256,
        4096,
    );
    if (!std.mem.startsWith(u8, help_response, "RESP 3 ")) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS6\n");
    if (std.mem.indexOf(u8, help_response, "OpenClaw bare-metal builtins:") == null) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, help_response, "shell-run") == null) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, help_response, "tty-send") == null) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, help_response, "workspace-suite-release-channel-activate") == null) return error.ToolServiceResponseMismatch;
    const put_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        put_request,
        512,
        256,
        512,
    );
    if (!std.mem.eql(u8, put_response, "RESP 21 40\nWROTE 52 bytes to /tools/scripts/net.oc\n")) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS7\n");

    const run_script_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 22 CMD run-script /tools/scripts/net.oc",
        512,
        256,
        512,
    );
    if (!std.mem.eql(u8, run_script_response, "RESP 22 38\nwrote 21 bytes to /tools/out/data.txt\n")) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS8\n");

    const get_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 23 GET /tools/out/data.txt",
        512,
        256,
        512,
    );
    if (!std.mem.eql(u8, get_response, "RESP 23 21\ntcp-service-persisted")) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9\n");

    const virtual_root_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 24 LIST /",
        256,
        256,
        256,
    );
    if (!std.mem.startsWith(u8, virtual_root_response, "RESP 24 ")) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, virtual_root_response, "dir tmp\n") == null) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, virtual_root_response, "dir dev\n") == null) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, virtual_root_response, "dir proc\n") == null) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, virtual_root_response, "dir sys\n") == null) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9A\n");

    const tmp_put_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 30 PUT /tmp/cache/tool.txt 4\nedge",
        512,
        256,
        512,
    );
    if (!std.mem.eql(u8, tmp_put_response, "RESP 30 37\nWROTE 4 bytes to /tmp/cache/tool.txt\n")) {
        return error.ToolServiceResponseMismatch;
    }
    qemuDebugWrite("ETS9A1\n");

    const tmp_get_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 31 GET /tmp/cache/tool.txt",
        256,
        256,
        256,
    );
    if (!std.mem.eql(u8, tmp_get_response, "RESP 31 4\nedge")) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9A2\n");

    const tmp_stat_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 32 STAT /tmp/cache/tool.txt",
        256,
        256,
        256,
    );
    if (!std.mem.eql(u8, tmp_stat_response, "RESP 32 42\npath=/tmp/cache/tool.txt kind=file size=4\n")) {
        return error.ToolServiceResponseMismatch;
    }
    qemuDebugWrite("ETS9A3\n");

    const tmp_list_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 33 LIST /tmp/cache",
        256,
        256,
        256,
    );
    if (!std.mem.eql(u8, tmp_list_response, "RESP 33 16\nfile tool.txt 4\n")) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9A4\n");

    const shell_run_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        shell_run_request,
        1536,
        256,
        1536,
    );
    if (!std.mem.startsWith(u8, shell_run_response, "RESP 34 ")) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, shell_run_response, "created /tmp/sh\n") == null) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, shell_run_response, "wrote 5 bytes to /tmp/sh/A.TXT\n") == null) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, shell_run_response, "created /tmp/sh/DATA\n") == null) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, shell_run_response, "created /tmp/sh/DATA/DEEP\n") == null) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, shell_run_response, "alpha\n") != null) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9A6\n");

    const shell_expand_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 35 SHELLEXPAND /tmp/sh/A*.TXT",
        256,
        256,
        256,
    );
    if (!std.mem.eql(u8, shell_expand_response, "RESP 35 14\n/tmp/sh/A.TXT\n")) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9A7\n");

    const shell_expand_nested_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 36 SHELLEXPAND /tmp/sh/DATA/*.TXT",
        256,
        256,
        256,
    );
    if (!std.mem.eql(u8, shell_expand_nested_response, "RESP 36 19\n/tmp/sh/DATA/C.TXT\n")) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9A8\n");

    const shell_expand_deep_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 37 SHELLEXPAND /tmp/sh/*/*/*.TXT",
        256,
        256,
        256,
    );
    if (!std.mem.eql(u8, shell_expand_deep_response, "RESP 37 24\n/tmp/sh/DATA/DEEP/Z.TXT\n")) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9A8B\n");

    const redirected_output_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 38 GET /tmp/sh/OUT.TXT",
        256,
        256,
        256,
    );
    if (!std.mem.eql(u8, redirected_output_response, "RESP 38 11\nalpha\nbeta\n")) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9A8C\n");

    const shell_stderr_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        shell_stderr_request,
        256,
        256,
        256,
    );
    if (!std.mem.eql(u8, shell_stderr_response, "RESP 42 11\nERR exit=1\n")) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9A8G\n");

    const redirected_stderr_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 43 GET /tmp/sh/ERR.TXT",
        256,
        256,
        256,
    );
    if (!std.mem.eql(u8, redirected_stderr_response, "RESP 43 25\ncat failed: FileNotFound\n")) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9A8H\n");

    const stdin_script = "echo stdin-shell > /tmp/sh/STDINOUT.TXT";
    const stdin_put_request = std.fmt.bufPrint(&rtl8139_tcp_probe_scratch.service_request_put_buffer, "REQ 44 PUT /tmp/sh/STDIN.OC {d}\n{s}", .{
        stdin_script.len,
        stdin_script,
    }) catch return error.ToolServiceFailed;
    const stdin_put_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        stdin_put_request,
        256,
        256,
        256,
    );
    if (!std.mem.eql(u8, stdin_put_response, "RESP 44 35\nWROTE 39 bytes to /tmp/sh/STDIN.OC\n")) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9A8I\n");

    const shell_input_script =
        "cat < /tmp/sh/A.TXT > /tmp/sh/COPY.TXT\n" ++
        "write-file /tmp/sh/FROMSTDIN.TXT < /tmp/sh/A.TXT\n" ++
        "write-file \"/tmp/sh/SPACE NAME.TXT\" spaced\n" ++
        "cat < \"/tmp/sh/SPACE NAME.TXT\" > /tmp/sh/QUOTE.TXT\n" ++
        "echo lt\\<value > /tmp/sh/LT.TXT\n" ++
        "shell-run < /tmp/sh/STDIN.OC";
    const shell_input_request = std.fmt.bufPrint(&rtl8139_tcp_probe_scratch.service_request_put_buffer, "REQ 45 SHELLRUN {d}\n{s}", .{
        shell_input_script.len,
        shell_input_script,
    }) catch return error.ToolServiceFailed;
    const shell_input_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        shell_input_request,
        1024,
        256,
        1024,
    );
    if (!std.mem.startsWith(u8, shell_input_response, "RESP 45 ")) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, shell_input_response, "wrote 5 bytes to /tmp/sh/FROMSTDIN.TXT\n") == null) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, shell_input_response, "wrote 6 bytes to /tmp/sh/SPACE NAME.TXT\n") == null) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9A8J\n");

    filesystem.createDirPath("/tmp/sh/CACHE DIR") catch return error.ToolServiceFailed;
    filesystem.writeFile("/tmp/sh/CACHE DIR/ITEM.TXT", "cache-item", 0) catch return error.ToolServiceFailed;
    filesystem.writeFile(
        "/tools/scripts/SPACE NAME.oc",
        "mkdir /tmp/sh/SCRIPT\nwrite-file /tmp/sh/SCRIPT/OUT.TXT script-space\n",
        0,
    ) catch return error.ToolServiceFailed;
    qemuDebugWrite("ETS9A8K\n");

    const copied_input_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 46 GET /tmp/sh/COPY.TXT",
        256,
        256,
        256,
    );
    if (!std.mem.eql(u8, copied_input_response, "RESP 46 5\nalpha")) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9A8K\n");

    const stdin_written_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 47 GET /tmp/sh/FROMSTDIN.TXT",
        256,
        256,
        256,
    );
    if (!std.mem.eql(u8, stdin_written_response, "RESP 47 5\nalpha")) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9A8L\n");

    const quoted_copy_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 48 GET /tmp/sh/QUOTE.TXT",
        256,
        256,
        256,
    );
    if (!std.mem.eql(u8, quoted_copy_response, "RESP 48 6\nspaced")) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9A8M\n");

    const nested_shell_input_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 50 GET /tmp/sh/STDINOUT.TXT",
        256,
        256,
        256,
    );
    if (!std.mem.eql(u8, nested_shell_input_response, "RESP 50 12\nstdin-shell\n")) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9A8O\n");

    const tty_open_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 51 TTYOPEN demo",
        256,
        256,
        256,
    );
    if (!std.mem.eql(u8, tty_open_response, "RESP 51 16\ntty opened demo\n")) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9A9A\n");

    const tty_write_body = "demo\nqueued-tty-input\n";
    const tty_write_request = std.fmt.bufPrint(&rtl8139_tcp_probe_scratch.service_request_put_buffer, "REQ 52 TTYWRITE {d}\n{s}", .{
        tty_write_body.len,
        tty_write_body,
    }) catch return error.ToolServiceFailed;
    const tty_write_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        tty_write_request,
        256,
        256,
        256,
    );
    if (!std.mem.eql(u8, tty_write_response, "RESP 52 25\ntty queued demo 17 bytes\n")) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9A9B\n");

    const tty_pending_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 53 TTYPENDING demo",
        256,
        256,
        256,
    );
    if (!std.mem.eql(u8, tty_pending_response, "RESP 53 17\nqueued-tty-input\n")) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9A9C\n");

    const tty_send_success_body = "demo cat";
    const tty_send_success_request = std.fmt.bufPrint(&rtl8139_tcp_probe_scratch.service_request_put_buffer, "REQ 54 TTYSEND {d}\n{s}", .{
        tty_send_success_body.len,
        tty_send_success_body,
    }) catch return error.ToolServiceFailed;
    const tty_send_success_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        tty_send_success_request,
        256,
        256,
        256,
    );
    if (!std.mem.eql(u8, tty_send_success_response, "RESP 54 17\nqueued-tty-input\n")) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9A9D\n");

    const tty_override_input_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 154 PUT /tmp/tty-input.txt 10\nfile-input",
        256,
        256,
        256,
    );
    if (!std.mem.startsWith(u8, tty_override_input_response, "RESP 154 ")) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, tty_override_input_response, "WROTE 10 bytes to /tmp/tty-input.txt\n") == null) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9A9D1\n");

    filesystem.writeFile("/tmp/tty input.txt", "tty spaced", 0) catch return error.ToolServiceFailed;
    qemuDebugWrite("ETS9A9D2\n");

    const tty_override_body = "demo\nqueued-tty-data";
    const tty_override_write_request = std.fmt.bufPrint(&rtl8139_tcp_probe_scratch.service_request_put_buffer, "REQ 156 TTYWRITE {d}\n{s}", .{
        tty_override_body.len,
        tty_override_body,
    }) catch return error.ToolServiceFailed;
    const tty_override_write_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        tty_override_write_request,
        256,
        256,
        256,
    );
    if (!std.mem.eql(u8, tty_override_write_response, "RESP 156 25\ntty queued demo 15 bytes\n")) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9A9D3\n");

    const tty_override_send_body = "demo cat < /tmp/tty-input.txt";
    const tty_override_send_request = std.fmt.bufPrint(&rtl8139_tcp_probe_scratch.service_request_put_buffer, "REQ 157 TTYSEND {d}\n{s}", .{
        tty_override_send_body.len,
        tty_override_send_body,
    }) catch return error.ToolServiceFailed;
    const tty_override_send_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        tty_override_send_request,
        256,
        256,
        256,
    );
    if (!std.mem.eql(u8, tty_override_send_response, "RESP 157 10\nfile-input")) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9A9D4\n");

    const tty_override_send_spaced_body = "demo cat < /tmp/tty\\ input.txt";
    const tty_override_send_spaced_request = std.fmt.bufPrint(&rtl8139_tcp_probe_scratch.service_request_put_buffer, "REQ 158 TTYSEND {d}\n{s}", .{
        tty_override_send_spaced_body.len,
        tty_override_send_spaced_body,
    }) catch return error.ToolServiceFailed;
    const tty_override_send_spaced_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        tty_override_send_spaced_request,
        256,
        256,
        256,
    );
    if (!std.mem.eql(u8, tty_override_send_spaced_response, "RESP 158 10\ntty spaced")) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9A9D5\n");

    const tty_pending_empty_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 55 TTYPENDING demo",
        256,
        256,
        256,
    );
    if (!std.mem.eql(u8, tty_pending_empty_response, "RESP 55 0\n")) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9A9E\n");

    const tty_clear_body = "demo\nstale-tty";
    const tty_clear_write_request = std.fmt.bufPrint(&rtl8139_tcp_probe_scratch.service_request_put_buffer, "REQ 56 TTYWRITE {d}\n{s}", .{
        tty_clear_body.len,
        tty_clear_body,
    }) catch return error.ToolServiceFailed;
    const tty_clear_write_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        tty_clear_write_request,
        256,
        256,
        256,
    );
    if (!std.mem.eql(u8, tty_clear_write_response, "RESP 56 24\ntty queued demo 9 bytes\n")) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9A9F\n");

    const tty_clear_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 57 TTYCLEAR demo",
        256,
        256,
        256,
    );
    if (!std.mem.eql(u8, tty_clear_response, "RESP 57 17\ntty cleared demo\n")) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9A9G\n");

    const tty_events_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 58 TTYEVENTS demo",
        1024,
        256,
        1024,
    );
    if (!std.mem.startsWith(u8, tty_events_response, "RESP 58 ")) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, tty_events_response, "type=open") == null) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, tty_events_response, "type=write bytes=17") == null) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, tty_events_response, "type=send exit=0 stdin_bytes=17 stdout_bytes=17 stderr_bytes=0") == null) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, tty_events_response, "type=write bytes=15") == null) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, tty_events_response, "type=send exit=0 stdin_bytes=15 stdout_bytes=10 stderr_bytes=0") == null) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, tty_events_response, "type=send exit=0 stdin_bytes=0 stdout_bytes=10 stderr_bytes=0") == null) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, tty_events_response, "type=clear bytes=9") == null) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9A9H\n");

    const tty_send_failure_body = "demo cat /tmp/missing-tty.txt";
    const tty_send_failure_request = std.fmt.bufPrint(&rtl8139_tcp_probe_scratch.service_request_put_buffer, "REQ 59 TTYSEND {d}\n{s}", .{
        tty_send_failure_body.len,
        tty_send_failure_body,
    }) catch return error.ToolServiceFailed;
    const tty_send_failure_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        tty_send_failure_request,
        256,
        256,
        256,
    );
    if (!std.mem.eql(u8, tty_send_failure_response, "RESP 59 36\nERR exit=1\ncat failed: FileNotFound\n")) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9A9I\n");

    const dev_tty_state_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 60 GET /dev/tty/state",
        256,
        256,
        256,
    );
    if (!std.mem.startsWith(u8, dev_tty_state_response, "RESP 60 ")) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, dev_tty_state_response, "sessions=1") == null) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, dev_tty_state_response, "open_sessions=1") == null) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, dev_tty_state_response, "pending_bytes=0") == null) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9A9J\n");

    const dev_tty_list_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 61 LIST /dev/tty/sessions",
        256,
        256,
        256,
    );
    if (!std.mem.startsWith(u8, dev_tty_list_response, "RESP 61 ")) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, dev_tty_list_response, "dir demo\n") == null) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9A9K\n");

    const dev_tty_info_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 62 GET /dev/tty/sessions/demo/info",
        768,
        256,
        768,
    );
    if (!std.mem.startsWith(u8, dev_tty_info_response, "RESP 62 ")) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, dev_tty_info_response, "name=demo") == null) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, dev_tty_info_response, "command_count=4") == null) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, dev_tty_info_response, "pending_input_bytes=0") == null) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, dev_tty_info_response, "event_count=9") == null) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9A9L\n");

    const dev_tty_pending_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 63 GET /dev/tty/sessions/demo/pending",
        256,
        256,
        256,
    );
    if (!std.mem.eql(u8, dev_tty_pending_response, "RESP 63 0\n")) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9A9M\n");

    const dev_tty_events_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 64 GET /dev/tty/sessions/demo/events",
        1024,
        256,
        1024,
    );
    if (!std.mem.startsWith(u8, dev_tty_events_response, "RESP 64 ")) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, dev_tty_events_response, "type=clear bytes=9") == null) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9A9N\n");

    const tty_read_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 65 TTYREAD demo",
        1536,
        256,
        1536,
    );
    if (!std.mem.startsWith(u8, tty_read_response, "RESP 65 ")) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, tty_read_response, "$ cat\n") == null) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, tty_read_response, "stdin:\nqueued-tty-input\n") == null) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, tty_read_response, "$ cat /tmp/missing-tty.txt\n") == null) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, tty_read_response, "stderr:\ncat failed: FileNotFound\n") == null) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9A9O\n");

    const tty_stdout_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 66 TTYSTDOUT demo",
        256,
        256,
        256,
    );
    if (!std.mem.eql(u8, tty_stdout_response, "RESP 66 37\nqueued-tty-input\nfile-inputtty spaced")) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9A9P\n");

    const tty_stderr_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 67 TTYSTDERR demo",
        256,
        256,
        256,
    );
    if (!std.mem.eql(u8, tty_stderr_response, "RESP 67 25\ncat failed: FileNotFound\n")) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9A9Q\n");

    const tty_close_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 68 TTYCLOSE demo",
        256,
        256,
        256,
    );
    if (!std.mem.eql(u8, tty_close_response, "RESP 68 16\ntty closed demo\n")) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9A9R\n");

    const sys_tty_state_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 69 GET /sys/tty/state",
        256,
        256,
        256,
    );
    if (!std.mem.startsWith(u8, sys_tty_state_response, "RESP 69 ")) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, sys_tty_state_response, "open_sessions=0") == null) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9A9S\n");

    const tty_shell_open_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 70 TTYOPEN shell",
        256,
        256,
        256,
    );
    if (!std.mem.eql(u8, tty_shell_open_response, "RESP 70 17\ntty opened shell\n")) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9A9T\n");

    const tty_shell_write_body = "shell\ntty-shell-input";
    const tty_shell_write_request = std.fmt.bufPrint(&rtl8139_tcp_probe_scratch.service_request_put_buffer, "REQ 71 TTYWRITE {d}\n{s}", .{
        tty_shell_write_body.len,
        tty_shell_write_body,
    }) catch return error.ToolServiceFailed;
    const tty_shell_write_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        tty_shell_write_request,
        256,
        256,
        256,
    );
    if (!std.mem.eql(u8, tty_shell_write_response, "RESP 71 26\ntty queued shell 15 bytes\n")) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9A9U\n");

    const tty_shell_script = "shell cat > /tmp/tty-shell/OUT.TXT; cat";
    const tty_shell_request = std.fmt.bufPrint(&rtl8139_tcp_probe_scratch.service_request_put_buffer, "REQ 72 TTYSHELL {d}\n{s}", .{
        tty_shell_script.len,
        tty_shell_script,
    }) catch return error.ToolServiceFailed;
    const tty_shell_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        tty_shell_request,
        256,
        256,
        256,
    );
    if (!std.mem.eql(u8, tty_shell_response, "RESP 72 15\ntty-shell-input")) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9A9V\n");

    const tty_shell_readback = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 73 GET /tmp/tty-shell/OUT.TXT",
        256,
        256,
        256,
    );
    if (!std.mem.eql(u8, tty_shell_readback, "RESP 73 15\ntty-shell-input")) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9A9W\n");

    const tty_shell_transcript = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 74 TTYREAD shell",
        1024,
        256,
        1024,
    );
    if (!std.mem.startsWith(u8, tty_shell_transcript, "RESP 74 ")) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, tty_shell_transcript, "$ shell-run\nscript:\ncat > /tmp/tty-shell/OUT.TXT; cat\n") == null) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, tty_shell_transcript, "stdin:\ntty-shell-input\n") == null) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9A9X\n");

    const tty_shell_events = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 75 TTYEVENTS shell",
        1024,
        256,
        1024,
    );
    if (!std.mem.startsWith(u8, tty_shell_events, "RESP 75 ")) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, tty_shell_events, "type=open") == null) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, tty_shell_events, "type=write bytes=15") == null) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, tty_shell_events, "type=shell exit=0 script_bytes=33 stdin_bytes=15 stdout_bytes=15 stderr_bytes=0") == null) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9A9Y\n");

    const tty_shell_close = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 76 TTYCLOSE shell",
        256,
        256,
        256,
    );
    if (!std.mem.eql(u8, tty_shell_close, "RESP 76 17\ntty closed shell\n")) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9A9Z\n");

    const quoted_path_write_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 77 CMD write-file \"/tmp/sh/QUO\\\"TE.TXT\" quoted",
        256,
        256,
        256,
    );
    if (!std.mem.startsWith(u8, quoted_path_write_response, "RESP 77 ")) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, quoted_path_write_response, "wrote 6 bytes to /tmp/sh/QUO\"TE.TXT\n") == null) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9AA\n");

    const quoted_path_shell_script =
        "cat \"/tmp/sh/QUO\\\"TE.TXT\" > /tmp/sh/QUOTED.TXT\n" ++
        "cat /tmp/sh/QUOTED.TXT";
    const quoted_path_shell_request = std.fmt.bufPrint(&rtl8139_tcp_probe_scratch.service_request_put_buffer, "REQ 78 SHELLRUN {d}\n{s}", .{
        quoted_path_shell_script.len,
        quoted_path_shell_script,
    }) catch return error.ToolServiceFailed;
    const quoted_path_shell_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        quoted_path_shell_request,
        256,
        256,
        256,
    );
    if (!std.mem.eql(u8, quoted_path_shell_response, "RESP 78 6\nquoted")) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9AB\n");

    const invalid_quoted_shell_script = "cat \"/tmp/sh/SPACE NAME.TXT\"x";
    const invalid_quoted_shell_request = std.fmt.bufPrint(&rtl8139_tcp_probe_scratch.service_request_put_buffer, "REQ 79 SHELLRUN {d}\n{s}", .{
        invalid_quoted_shell_script.len,
        invalid_quoted_shell_script,
    }) catch return error.ToolServiceFailed;
    const invalid_quoted_shell_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        invalid_quoted_shell_request,
        256,
        256,
        256,
    );
    if (!std.mem.startsWith(u8, invalid_quoted_shell_response, "RESP 79 ")) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, invalid_quoted_shell_response, "ERR exit=2\nusage: cat <path>\n") == null) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9AC\n");

    const direct_space_cat_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 80 CMD cat /tmp/sh/SPACE\\ NAME.TXT",
        256,
        256,
        256,
    );
    if (!std.mem.eql(u8, direct_space_cat_response, "RESP 80 6\nspaced")) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9AD\n");

    const direct_space_write_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 81 CMD write-file /tmp/sh/CMD\\ SPACE.TXT cmd-space",
        256,
        256,
        256,
    );
    if (!std.mem.startsWith(u8, direct_space_write_response, "RESP 81 ")) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, direct_space_write_response, "wrote 9 bytes to /tmp/sh/CMD SPACE.TXT\n") == null) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9AE\n");

    const direct_space_write_readback = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 82 GET /tmp/sh/CMD SPACE.TXT",
        256,
        256,
        256,
    );
    if (!std.mem.eql(u8, direct_space_write_readback, "RESP 82 9\ncmd-space")) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9AF\n");

    const direct_mount_bind_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
    const direct_mount_readback = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 179 GET /mnt/cache/ITEM.TXT",
        256,
        256,
        256,
    );
    const direct_run_script_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 180 CMD run-script /tools/scripts/SPACE\\ NAME.oc",
        512,
        256,
        512,
    );
    if (!std.mem.startsWith(u8, direct_run_script_response, "RESP 180 ")) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, direct_run_script_response, "wrote 12 bytes to /tmp/sh/SCRIPT/OUT.TXT\n") == null) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9AF3\n");

    const direct_run_script_readback = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 181 GET /tmp/sh/SCRIPT/OUT.TXT",
        256,
        256,
        256,
    );
    if (!std.mem.eql(u8, direct_run_script_readback, "RESP 181 12\nscript-space")) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9AF4\n");

    const tty_shell_override_input_put = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 83 PUT /tmp/tty-shell/INPUT.TXT 10\nfile-input",
        256,
        256,
        256,
    );
    if (!std.mem.startsWith(u8, tty_shell_override_input_put, "RESP 83 ")) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, tty_shell_override_input_put, "WROTE 10 bytes to /tmp/tty-shell/INPUT.TXT\n") == null) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9B0\n");

    filesystem.writeFile("/tmp/tty-shell/SPACE NAME.TXT", "space-file", 0) catch return error.ToolServiceFailed;
    qemuDebugWrite("ETS9AD1\n");

    const tty_shell_override_open = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 84 TTYOPEN shell-override",
        256,
        256,
        256,
    );
    if (!std.mem.eql(u8, tty_shell_override_open, "RESP 84 26\ntty opened shell-override\n")) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9B1\n");

    const tty_shell_override_body = "shell-override\nqueued-tty-data";
    const tty_shell_override_write_request = std.fmt.bufPrint(&rtl8139_tcp_probe_scratch.service_request_put_buffer, "REQ 85 TTYWRITE {d}\n{s}", .{
        tty_shell_override_body.len,
        tty_shell_override_body,
    }) catch return error.ToolServiceFailed;
    const tty_shell_override_write = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        tty_shell_override_write_request,
        256,
        256,
        256,
    );
    if (!std.mem.eql(u8, tty_shell_override_write, "RESP 85 35\ntty queued shell-override 15 bytes\n")) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9B2\n");

    const tty_shell_override_batch = "cat < \"/tmp/tty-shell/INPUT.TXT\" > /tmp/tty-shell/OVERRIDE.TXT; cat";
    const tty_shell_override_script = "shell-override cat < \"/tmp/tty-shell/INPUT.TXT\" > /tmp/tty-shell/OVERRIDE.TXT; cat";
    const tty_shell_override_request = std.fmt.bufPrint(&rtl8139_tcp_probe_scratch.service_request_put_buffer, "REQ 86 TTYSHELL {d}\n{s}", .{
        tty_shell_override_script.len,
        tty_shell_override_script,
    }) catch return error.ToolServiceFailed;
    const tty_shell_override_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        tty_shell_override_request,
        256,
        256,
        256,
    );
    if (!std.mem.eql(u8, tty_shell_override_response, "RESP 86 15\nqueued-tty-data")) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9B3\n");

    const tty_shell_override_readback = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 87 GET /tmp/tty-shell/OVERRIDE.TXT",
        256,
        256,
        256,
    );
    if (!std.mem.eql(u8, tty_shell_override_readback, "RESP 87 10\nfile-input")) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9B4\n");

    const tty_shell_space_write_body = "shell-override\nqueued-space-data";
    const tty_shell_space_write_request = std.fmt.bufPrint(&rtl8139_tcp_probe_scratch.service_request_put_buffer, "REQ 175 TTYWRITE {d}\n{s}", .{
        tty_shell_space_write_body.len,
        tty_shell_space_write_body,
    }) catch return error.ToolServiceFailed;
    const tty_shell_space_write_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        tty_shell_space_write_request,
        256,
        256,
        256,
    );
    if (!std.mem.eql(u8, tty_shell_space_write_response, "RESP 175 35\ntty queued shell-override 17 bytes\n")) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9AH1\n");

    const tty_shell_space_batch = "cat < /tmp/tty-shell/SPACE\\ NAME.TXT > /tmp/tty-shell/SPACEOUT.TXT; cat";
    const tty_shell_space_script = "shell-override cat < /tmp/tty-shell/SPACE\\ NAME.TXT > /tmp/tty-shell/SPACEOUT.TXT; cat";
    const tty_shell_space_request = std.fmt.bufPrint(&rtl8139_tcp_probe_scratch.service_request_put_buffer, "REQ 176 TTYSHELL {d}\n{s}", .{
        tty_shell_space_script.len,
        tty_shell_space_script,
    }) catch return error.ToolServiceFailed;
    const tty_shell_space_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        tty_shell_space_request,
        256,
        256,
        256,
    );
    if (!std.mem.eql(u8, tty_shell_space_response, "RESP 176 17\nqueued-space-data")) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9AH2\n");

    const tty_shell_space_readback = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 177 GET /tmp/tty-shell/SPACEOUT.TXT",
        256,
        256,
        256,
    );
    if (!std.mem.eql(u8, tty_shell_space_readback, "RESP 177 10\nspace-file")) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9AH3\n");

    const tty_shell_override_pending = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 88 TTYPENDING shell-override",
        256,
        256,
        256,
    );
    if (!std.mem.eql(u8, tty_shell_override_pending, "RESP 88 0\n")) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9B5\n");

    const tty_shell_override_events = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 89 TTYEVENTS shell-override",
        1024,
        256,
        1024,
    );
    if (!std.mem.startsWith(u8, tty_shell_override_events, "RESP 89 ")) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, tty_shell_override_events, "type=write bytes=15") == null) return error.ToolServiceResponseMismatch;
    var tty_shell_override_event_buffer: [128]u8 = undefined;
    const tty_shell_override_event = std.fmt.bufPrint(&tty_shell_override_event_buffer, "type=shell exit=0 script_bytes={d} stdin_bytes=15 stdout_bytes=15 stderr_bytes=0", .{tty_shell_override_batch.len}) catch return error.ToolServiceFailed;
    if (std.mem.indexOf(u8, tty_shell_override_events, tty_shell_override_event) == null) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, tty_shell_override_events, "type=write bytes=17") == null) return error.ToolServiceResponseMismatch;
    var tty_shell_space_event_buffer: [128]u8 = undefined;
    const tty_shell_space_event = std.fmt.bufPrint(&tty_shell_space_event_buffer, "type=shell exit=0 script_bytes={d} stdin_bytes=17 stdout_bytes=17 stderr_bytes=0", .{tty_shell_space_batch.len}) catch return error.ToolServiceFailed;
    if (std.mem.indexOf(u8, tty_shell_override_events, tty_shell_space_event) == null) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9B6\n");

    const tty_shell_override_close = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 90 TTYCLOSE shell-override",
        256,
        256,
        256,
    );
    if (!std.mem.eql(u8, tty_shell_override_close, "RESP 90 26\ntty closed shell-override\n")) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9B7\n");

    const virtual_storage_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 26 GET /sys/storage/state",
        512,
        256,
        512,
    );
    if (!std.mem.startsWith(u8, virtual_storage_response, "RESP 26 ")) return error.ToolServiceResponseMismatch;
    const expected_storage_backend = switch (storage_backend.activeBackend()) {
        abi.storage_backend_ram_disk => "backend=ram_disk",
        abi.storage_backend_ata_pio => "backend=ata_pio",
        abi.storage_backend_virtio_block => "backend=virtio_block",
        else => return error.ToolServiceResponseMismatch,
    };
    if (std.mem.indexOf(u8, virtual_storage_response, expected_storage_backend) == null) {
        return error.ToolServiceResponseMismatch;
    }
    qemuDebugWrite("ETS9C\n");

    const virtual_dev_listing = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 28 LIST /dev",
        256,
        256,
        256,
    );
    if (!std.mem.startsWith(u8, virtual_dev_listing, "RESP 28 ")) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, virtual_dev_listing, "dir storage\n") == null) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, virtual_dev_listing, "dir display\n") == null) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, virtual_dev_listing, "dir net\n") == null) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, virtual_dev_listing, "file null 0\n") == null) return error.ToolServiceResponseMismatch;
    qemuDebugWrite("ETS9E\n");

    const virtual_dev_storage_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
        "REQ 29 GET /dev/storage/state",
        512,
        256,
        512,
    );
    if (!std.mem.startsWith(u8, virtual_dev_storage_response, "RESP 29 ")) return error.ToolServiceResponseMismatch;
    if (std.mem.indexOf(u8, virtual_dev_storage_response, expected_storage_backend) == null) {
        return error.ToolServiceResponseMismatch;
    }
    qemuDebugWrite("ETS9F\n");

    const virtual_stat_response = try exchangeE1000TcpProbeServiceRequest(
        eth,
        scratch,
        &client,
        &server,
        source_ip,
        destination_ip,
    _ = try sendE1000TcpProbeSegment(source_ip, destination_ip, client.local_port, client.remote_port, client_fin);
    try pollE1000TcpProbePacket(eth, &scratch.packet_storage);
    try expectE1000TcpProbePacket(&scratch.packet_storage, eth.mac, source_ip, destination_ip, client.local_port, client.remote_port, client_fin);
    _ = try sendE1000TcpProbeSegment(destination_ip, source_ip, server.local_port, server.remote_port, fin_ack);
    try pollE1000TcpProbePacket(eth, &scratch.packet_storage);
    try expectE1000TcpProbePacket(&scratch.packet_storage, eth.mac, destination_ip, source_ip, server.local_port, server.remote_port, fin_ack);
    _ = try sendE1000TcpProbeSegment(destination_ip, source_ip, server.local_port, server.remote_port, server_fin);
    try pollE1000TcpProbePacket(eth, &scratch.packet_storage);
    try expectE1000TcpProbePacket(&scratch.packet_storage, eth.mac, destination_ip, source_ip, server.local_port, server.remote_port, server_fin);
    _ = try sendE1000TcpProbeSegment(source_ip, destination_ip, client.local_port, client.remote_port, final_ack);
    try pollE1000TcpProbePacket(eth, &scratch.packet_storage);
    try expectE1000TcpProbePacket(&scratch.packet_storage, eth.mac, source_ip, destination_ip, client.local_port, client.remote_port, final_ack);
fn runE1000FullStackProbe() E1000ToolServiceProbeError!void {
    try runE1000ToolServiceProbe();
}

fn runRtl8139HttpsPostProbe() Rtl8139TcpProbeError!void {
    setProbeInterruptsEnabled(false);

    rtl8139.initDetailed() catch |err| return switch (err) {
        error.UnsupportedPlatform => error.UnsupportedPlatform,
        error.DeviceNotFound => error.DeviceNotFound,
        error.ResetTimeout => error.ResetTimeout,
        error.BufferProgramFailed => error.BufferProgramFailed,
        error.MacReadFailed => error.MacReadFailed,
    e1000.resetForTest();
    virtio_net.resetForTest();
    rtl8139.resetForTest();
    storage_backend.resetForTest();
    ps2_input.resetForTest();
    tool_layout.resetForTest();
    filesystem.resetForTest();
    pal_net.selectBackend(.rtl8139);
    pal_net.clearRouteState();
}

test "baremetal e1000 raw frame transport loops through mock e1000 and exports stable state" {
    resetBaremetalRuntimeForTest();
    e1000.testEnableMockDevice();
    defer e1000.testDisableMockDevice();

    try runE1000Probe();
    const eth = e1000.statePtr();
    try std.testing.expectEqual(@as(u32, abi.ethernet_magic), eth.magic);
    try std.testing.expectEqual(@as(u8, abi.ethernet_backend_e1000), eth.backend);
    try std.testing.expectEqual(@as(u8, 1), eth.initialized);
    try std.testing.expectEqual(@as(u8, 1), eth.loopback_enabled);
    try std.testing.expectEqual(@as(u32, 1), eth.tx_packets);
    try std.testing.expectEqual(@as(u32, 1), eth.rx_packets);
}

test "baremetal virtio net raw frame transport loops through mock virtio net and exports stable state" {
    resetBaremetalRuntimeForTest();
    virtio_net.testEnableMockDevice();
    defer virtio_net.testDisableMockDevice();

    try runVirtioNetProbe();
    const eth = virtio_net.statePtr();
    try std.testing.expectEqual(@as(u8, abi.ethernet_backend_virtio_net), eth.backend);
    try std.testing.expectEqual(@as(u32, 96), eth.last_rx_len);
}

test "baremetal virtio net arp request loops through mock virtio net and parses request" {
    resetBaremetalRuntimeForTest();
    virtio_net.testEnableMockDevice();
    defer virtio_net.testDisableMockDevice();

    try runVirtioNetArpProbe();
    try std.testing.expectEqual(@as(u8, abi.ethernet_backend_virtio_net), virtio_net.statePtr().backend);
}

test "baremetal virtio net ipv4 probe succeeds through mock device" {
    resetBaremetalRuntimeForTest();
    virtio_net.testEnableMockDevice();
    defer virtio_net.testDisableMockDevice();

    try runVirtioNetIpv4Probe();
}

test "baremetal virtio net udp probe succeeds through mock device" {
    resetBaremetalRuntimeForTest();
    virtio_net.testEnableMockDevice();
    defer virtio_net.testDisableMockDevice();

    try runVirtioNetUdpProbe();
}

test "baremetal virtio net dhcp probe succeeds through mock device" {
    resetBaremetalRuntimeForTest();
    virtio_net.testEnableMockDevice();
    defer virtio_net.testDisableMockDevice();

    try runVirtioNetDhcpProbe();
}

test "baremetal virtio net dns probe succeeds through mock device" {
    resetBaremetalRuntimeForTest();
    virtio_net.testEnableMockDevice();
    defer virtio_net.testDisableMockDevice();

    try runVirtioNetDnsProbe();
}

test "baremetal virtio net tcp probe succeeds through mock device" {
    resetBaremetalRuntimeForTest();
    virtio_net.testEnableMockDevice();
    defer virtio_net.testDisableMockDevice();

    try runVirtioNetTcpProbe();
}

test "baremetal virtio net http post probe succeeds through mock device" {
    resetBaremetalRuntimeForTest();
    virtio_net.testEnableMockDevice();
    defer virtio_net.testDisableMockDevice();

    try runVirtioNetHttpPostProbe();
}

test "baremetal virtio net tool service probe succeeds through mock device" {
    resetBaremetalRuntimeForTest();
    virtio_net.testEnableMockDevice();
    defer virtio_net.testDisableMockDevice();

    try runVirtioNetToolServiceProbe();
}

test "baremetal e1000 arp request loops through mock e1000 and parses request" {
    resetBaremetalRuntimeForTest();
    e1000.testEnableMockDevice();
    defer e1000.testDisableMockDevice();

    try runE1000ArpProbe();
    try std.testing.expectEqual(@as(u8, abi.ethernet_backend_e1000), e1000.statePtr().backend);
}

test "baremetal e1000 ipv4 probe succeeds through mock device" {
    resetBaremetalRuntimeForTest();
    e1000.testEnableMockDevice();
    defer e1000.testDisableMockDevice();

    try runE1000Ipv4Probe();
}

test "baremetal e1000 udp probe succeeds through mock device" {
    resetBaremetalRuntimeForTest();
    e1000.testEnableMockDevice();
    defer e1000.testDisableMockDevice();

    try runE1000UdpProbe();
}

test "baremetal e1000 dhcp probe succeeds through mock device" {
    resetBaremetalRuntimeForTest();
    e1000.testEnableMockDevice();
    defer e1000.testDisableMockDevice();

    try runE1000DhcpProbe();
}

test "baremetal e1000 dns probe succeeds through mock device" {
    resetBaremetalRuntimeForTest();
    e1000.testEnableMockDevice();
    defer e1000.testDisableMockDevice();

    try runE1000DnsProbe();
}

test "baremetal e1000 tcp probe succeeds through mock device" {
    resetBaremetalRuntimeForTest();
    e1000.testEnableMockDevice();
    defer e1000.testDisableMockDevice();

    try runE1000TcpProbe();
}

test "baremetal e1000 http post probe succeeds through mock device" {
    resetBaremetalRuntimeForTest();
    e1000.testEnableMockDevice();
    defer e1000.testDisableMockDevice();

    try runE1000HttpPostProbe();
}

test "baremetal e1000 tool service probe succeeds through mock device" {
    resetBaremetalRuntimeForTest();
    e1000.testEnableMockDevice();
    defer e1000.testDisableMockDevice();

    try runE1000ToolServiceProbe();
}

test "baremetal e1000 full stack probe succeeds through mock device" {
    resetBaremetalRuntimeForTest();
    e1000.testEnableMockDevice();
    defer e1000.testDisableMockDevice();

    try runE1000FullStackProbe();
}

test "baremetal ethernet arp request loops through mock rtl8139 and parses request" {
    resetBaremetalRuntimeForTest();
    rtl8139.testEnableMockDevice();
    defer rtl8139.testDisableMockDevice();

    try std.testing.expectEqual(@as(u8, 1), oc_ethernet_init());
    const eth = oc_ethernet_state_ptr();
    const sender_ip = [4]u8{ 192, 168, 56, 10 };
    const target_ip = [4]u8{ 192, 168, 56, 1 };

    try std.testing.expectEqual(@as(u32, arp_protocol.frame_len), try pal_net.sendArpRequest(sender_ip, target_ip));
    const packet = (try pal_net.pollArpPacket()).?;

    try std.testing.expectEqual(arp_protocol.operation_request, packet.operation);
    try std.testing.expectEqualSlices(u8, ethernet_protocol.broadcast_mac[0..], packet.ethernet_destination[0..]);
    try std.testing.expectEqualSlices(u8, eth.mac[0..], packet.ethernet_source[0..]);
    try std.testing.expectEqualSlices(u8, eth.mac[0..], packet.sender_mac[0..]);
    try std.testing.expectEqualSlices(u8, sender_ip[0..], packet.sender_ip[0..]);
    try std.testing.expectEqualSlices(u8, target_ip[0..], packet.target_ip[0..]);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0, 0, 0, 0, 0, 0 }, packet.target_mac[0..]);
    try std.testing.expectEqual(@as(u32, 1), eth.tx_packets);
    try std.testing.expectEqual(@as(u32, 1), eth.rx_packets);
    try std.testing.expect(eth.last_rx_len >= arp_protocol.frame_len);
}

test "baremetal rtl8139 ipv4 probe succeeds through mock device" {
    resetBaremetalRuntimeForTest();
    rtl8139.testEnableMockDevice();
    defer rtl8139.testDisableMockDevice();

    try runRtl8139Ipv4Probe();
}

test "baremetal rtl8139 udp probe succeeds through mock device" {
    resetBaremetalRuntimeForTest();
    rtl8139.testEnableMockDevice();
    defer rtl8139.testDisableMockDevice();

    try runRtl8139UdpProbe();
}

test "baremetal rtl8139 tcp probe succeeds through mock device" {
    resetBaremetalRuntimeForTest();
    rtl8139.testEnableMockDevice();
    defer rtl8139.testDisableMockDevice();

    try runRtl8139TcpProbe();
}

test "baremetal rtl8139 http post probe succeeds through mock device" {
    resetBaremetalRuntimeForTest();
    rtl8139.testEnableMockDevice();
    defer rtl8139.testDisableMockDevice();

    try runRtl8139HttpPostProbe();
}

test "baremetal rtl8139 dhcp probe succeeds through mock device" {
    resetBaremetalRuntimeForTest();
    rtl8139.testEnableMockDevice();
    defer rtl8139.testDisableMockDevice();

    try runRtl8139DhcpProbe();
}

test "baremetal rtl8139 dns probe succeeds through mock device" {
    resetBaremetalRuntimeForTest();
    rtl8139.testEnableMockDevice();
    defer rtl8139.testDisableMockDevice();

    try runRtl8139DnsProbe();
}

test "baremetal rtl8139 gateway routing probe succeeds through mock device" {
    resetBaremetalRuntimeForTest();
    rtl8139.testEnableMockDevice();
    defer rtl8139.testDisableMockDevice();

    try runRtl8139GatewayProbe();
}

test "baremetal tool exec probe succeeds through pal proc freestanding path" {
    try runToolExecProbe();
}

test "baremetal tool runtime probe succeeds through freestanding runtime path" {
    if (builtin.os.tag != .freestanding) return error.SkipZigTest;
    try runToolRuntimeProbe();
}

test "baremetal storage export surface persists block writes and flush state" {
    resetBaremetalRuntimeForTest();

    oc_storage_init();
    const storage = oc_storage_state_ptr();
    try std.testing.expectEqual(@as(u32, abi.storage_magic), storage.magic);
