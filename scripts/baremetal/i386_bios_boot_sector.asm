; SPDX-License-Identifier: GPL-2.0-only
[bits 16]
[org 0x7C00]

%ifndef STAGE2_LOAD_SEGMENT
%define STAGE2_LOAD_SEGMENT 0x07E0
%endif

%ifndef STAGE2_SECTORS
%define STAGE2_SECTORS 16
%endif

start:
    cli
    cld
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00

    mov [boot_drive], dl

    mov si, disk_packet
    mov ah, 0x42
    mov dl, [boot_drive]
    int 0x13
    jc boot_failed

    jmp STAGE2_LOAD_SEGMENT:0x0000

boot_failed:
    mov dx, 0x00E9
    mov al, 'B'
    out dx, al
.hang:
    cli
    hlt
    jmp .hang

boot_drive:
    db 0

disk_packet:
    db 0x10
    db 0
    dw STAGE2_SECTORS
    dw 0x0000
    dw STAGE2_LOAD_SEGMENT
    dq 1

times 510 - ($ - $$) db 0
dw 0xAA55
