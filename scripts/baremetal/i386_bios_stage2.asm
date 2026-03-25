; SPDX-License-Identifier: GPL-2.0-only
[bits 16]
[org 0x7E00]

%ifndef HEADER_LBA
%define HEADER_LBA 17
%endif

%define HEADER_MAGIC          0x3146525A
%define HEADER_VERSION        1
%define HEADER_DESC_SIZE      20
%define HEADER_DESC_OFFSET    16
%define MULTIBOOT_INFO_ADDR   0x00000800
%define HEADER_BUFFER_ADDR    0x00001000
%define CHUNK_BUFFER_ADDR     0x00010000
%define CHUNK_BUFFER_SECTORS  32
%define STACK_TOP_REAL        0x7C00
%define STACK_TOP_PROTECTED   0x00070000

%define MULTIBOOT2_BOOT_MAGIC         0x36D76289
%define MULTIBOOT2_TAG_TYPE_END       0
%define MULTIBOOT2_TAG_TYPE_BASIC_MEM 4
%define MULTIBOOT2_TAG_TYPE_MEMORY_MAP 6
%define MULTIBOOT2_MEMORY_MAP_ENTRY_SIZE 24
%define E820_SIGNATURE                0x534D4150
%define CMOS_ADDR_PORT                0x70
%define CMOS_DATA_PORT                0x71
%define CMOS_EXT_LOW_LOW              0x30
%define CMOS_EXT_LOW_HIGH             0x31
%define CMOS_EXT_HIGH_LOW             0x34
%define CMOS_EXT_HIGH_HIGH            0x35

%define DESC_DEST_ADDR        0
%define DESC_LBA              4
%define DESC_SECTOR_COUNT     8
%define DESC_FILE_SIZE        12
%define DESC_MEM_SIZE         16

stage2_start:
    cli
    cld
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, STACK_TOP_REAL
    mov [boot_drive], dl
    call debug_mark_s

    call debug_mark_h
    mov word [disk_packet.sector_count], 1
    mov word [disk_packet.buffer_offset], HEADER_BUFFER_ADDR
    mov word [disk_packet.buffer_segment], 0x0000
    mov dword [disk_packet.lba_low], HEADER_LBA
    mov dword [disk_packet.lba_high], 0
    call bios_extended_read

    cmp dword [HEADER_BUFFER_ADDR + 0], HEADER_MAGIC
    jne bad_header
    cmp word [HEADER_BUFFER_ADDR + 4], HEADER_VERSION
    jne bad_header
    mov eax, [HEADER_BUFFER_ADDR + 8]
    mov [kernel_entry_addr], eax

    call debug_mark_p
    mov cx, [HEADER_BUFFER_ADDR + 6]
    mov si, HEADER_BUFFER_ADDR + HEADER_DESC_OFFSET

segment_loop:
    test cx, cx
    jz enter_kernel_mode

    push cx
    mov bx, [HEADER_BUFFER_ADDR + 6]
    sub bx, cx
    call debug_segment_index
    pop cx

    mov eax, [si + DESC_DEST_ADDR]
    mov [current_dest], eax
    mov eax, [si + DESC_LBA]
    mov [current_lba], eax
    mov eax, [si + DESC_FILE_SIZE]
    mov [current_file_size], eax
    mov eax, [si + DESC_MEM_SIZE]
    mov [current_mem_size], eax

load_payload_loop:
    mov eax, [current_file_size]
    test eax, eax
    jz zero_segment_tail

    cmp eax, CHUNK_BUFFER_SECTORS * 512
    jbe have_chunk_bytes
    mov eax, CHUNK_BUFFER_SECTORS * 512
have_chunk_bytes:
    mov [current_chunk_bytes], eax
    add eax, 511
    shr eax, 9
    mov [current_chunk_sectors], ax

    mov ax, [current_chunk_sectors]
    mov [disk_packet.sector_count], ax
    mov word [disk_packet.buffer_offset], 0x0000
    mov word [disk_packet.buffer_segment], CHUNK_BUFFER_ADDR >> 4
    mov eax, [current_lba]
    mov [disk_packet.lba_low], eax
    mov dword [disk_packet.lba_high], 0
    call bios_extended_read

    push si
    call enter_unreal_mode
    mov esi, CHUNK_BUFFER_ADDR
    mov edi, [current_dest]
    push cx
    mov ecx, [current_chunk_bytes]
    a32 rep movsb
    pop cx
    call restore_real_segments
    pop si

    mov eax, [current_dest]
    add eax, [current_chunk_bytes]
    mov [current_dest], eax

    movzx eax, word [current_chunk_sectors]
    add [current_lba], eax

    mov eax, [current_file_size]
    sub eax, [current_chunk_bytes]
    mov [current_file_size], eax
    jmp load_payload_loop

zero_segment_tail:
    mov eax, [current_mem_size]
    mov edx, [si + DESC_FILE_SIZE]
    cmp eax, edx
    ja zero_segment_tail_needed
    jmp next_segment

zero_segment_tail_needed:
    sub eax, edx
    push cx
    mov ecx, eax
    call enter_unreal_mode
    mov edi, [si + DESC_DEST_ADDR]
    add edi, edx
    xor eax, eax
    a32 rep stosb
    pop cx
    call restore_real_segments

next_segment:
    push cx
    mov bx, [HEADER_BUFFER_ADDR + 6]
    sub bx, cx
    call debug_segment_done
    pop cx
    add si, HEADER_DESC_SIZE
    dec cx
    jmp segment_loop

enter_kernel_mode:
    call build_multiboot_info
    call enter_unreal_mode
    call debug_mark_j
    cli
    mov eax, cr0
    or eax, 0x1
    mov cr0, eax
    jmp 0x18:protected_mode_start

bad_header:
    call debug_mark_m
    jmp load_failed

bios_read_failed:
    call debug_mark_e
    push ax
    mov al, ah
    call debug_hex_byte
    pop ax
    jmp load_failed

load_failed:
    call debug_mark_l
.hang:
    cli
    hlt
    jmp .hang

bios_extended_read:
    push si
    mov si, disk_packet
    mov ah, 0x42
    mov dl, [boot_drive]
    int 0x13
    jnc .ok
    pop si
    jc bios_read_failed
.ok:
    pop si
    ret

enter_unreal_mode:
    lgdt [gdt_descriptor]
    mov eax, cr0
    or eax, 0x1
    mov cr0, eax
    jmp 0x08:protected_unreal_setup

protected_unreal_setup:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov eax, cr0
    and eax, 0xFFFFFFFE
    mov cr0, eax
    jmp 0x07E0:unreal_return - stage2_start

unreal_return:
    ret

restore_real_segments:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    ret

build_multiboot_info:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push es

    mov di, MULTIBOOT_INFO_ADDR
    mov dword [di + 0], 0
    mov dword [di + 4], 0
    mov dword [di + 8], MULTIBOOT2_TAG_TYPE_BASIC_MEM
    mov dword [di + 12], 16

    int 0x12
    movzx edx, ax
    mov dword [di + 16], edx

    call read_extended_memory_kib
    mov dword [di + 20], eax

    mov si, MULTIBOOT_INFO_ADDR + 24
    call build_multiboot_memory_map_tag
    add si, 7
    and si, 0xFFF8
    mov dword [si + 0], MULTIBOOT2_TAG_TYPE_END
    mov dword [si + 4], 8
    add si, 8
    xor eax, eax
    mov ax, si
    sub eax, MULTIBOOT_INFO_ADDR
    mov dword [MULTIBOOT_INFO_ADDR + 0], eax

    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

build_multiboot_memory_map_tag:
    mov word [e820_entry_count], 0
    mov word [e820_tag_addr], si

    mov dword [si + 0], MULTIBOOT2_TAG_TYPE_MEMORY_MAP
    mov dword [si + 4], 16
    mov dword [si + 8], MULTIBOOT2_MEMORY_MAP_ENTRY_SIZE
    mov dword [si + 12], 0
    add si, 16
    xor eax, eax
    mov dword [e820_continuation], eax

.loop:
    mov ax, si
    add ax, MULTIBOOT2_MEMORY_MAP_ENTRY_SIZE + 8
    cmp ax, HEADER_BUFFER_ADDR
    jae .omit

    xor eax, eax
    mov dword [si + 0], eax
    mov dword [si + 4], eax
    mov dword [si + 8], eax
    mov dword [si + 12], eax
    mov dword [si + 16], eax
    mov dword [si + 20], 1

    xor ax, ax
    mov es, ax
    mov di, si
    mov eax, 0xE820
    mov edx, E820_SIGNATURE
    mov ecx, MULTIBOOT2_MEMORY_MAP_ENTRY_SIZE
    mov ebx, [e820_continuation]
    int 0x15
    jc .done
    cmp eax, E820_SIGNATURE
    jne .done
    mov [e820_continuation], ebx
    cmp ecx, 20
    jb .next
    mov eax, [si + 8]
    or eax, [si + 12]
    jz .next
    inc word [e820_entry_count]
    add si, MULTIBOOT2_MEMORY_MAP_ENTRY_SIZE

.next:
    mov eax, [e820_continuation]
    test eax, eax
    jnz .loop

.done:
    cmp word [e820_entry_count], 0
    je .omit
    mov bx, [e820_tag_addr]
    mov ax, [e820_entry_count]
    mov cx, MULTIBOOT2_MEMORY_MAP_ENTRY_SIZE
    mul cx
    add ax, 16
    adc dx, 0
    mov word [bx + 4], ax
    mov word [bx + 6], dx
    ret

.omit:
    mov si, [e820_tag_addr]
    ret

read_extended_memory_kib:
    push bx

    mov al, CMOS_EXT_HIGH_HIGH
    call read_cmos_byte
    movzx eax, al
    shl eax, 8
    mov al, CMOS_EXT_HIGH_LOW
    call read_cmos_byte
    movzx ebx, al
    or eax, ebx
    test eax, eax
    jz .legacy
    shl eax, 6
    add eax, 15 * 1024
    pop bx
    ret

.legacy:
    mov al, CMOS_EXT_LOW_HIGH
    call read_cmos_byte
    movzx eax, al
    shl eax, 8
    mov al, CMOS_EXT_LOW_LOW
    call read_cmos_byte
    movzx ebx, al
    or eax, ebx
    pop bx
    ret

read_cmos_byte:
    push dx
    or al, 0x80
    mov dx, CMOS_ADDR_PORT
    out dx, al
    mov dx, CMOS_DATA_PORT
    in al, dx
    pop dx
    ret

[bits 32]
protected_mode_start:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, STACK_TOP_PROTECTED
    mov eax, MULTIBOOT2_BOOT_MAGIC
    mov ebx, MULTIBOOT_INFO_ADDR
    mov edx, [kernel_entry_addr]
    jmp edx

[bits 16]
enable_a20:
    in al, 0x92
    or al, 0x02
    and al, 0xFE
    out 0x92, al
    ret

debug_emit:
    mov dx, 0x00E9
    out dx, al
    ret

debug_mark_s:
    mov al, 'S'
    jmp debug_emit

debug_mark_g:
    mov al, 'G'
    jmp debug_emit

debug_mark_r:
    mov al, 'R'
    jmp debug_emit

debug_mark_h:
    mov al, 'H'
    jmp debug_emit

debug_mark_p:
    mov al, 'P'
    jmp debug_emit

debug_mark_j:
    mov al, 'J'
    jmp debug_emit

debug_mark_m:
    mov al, 'M'
    jmp debug_emit

debug_mark_e:
    mov al, 'E'
    jmp debug_emit

debug_mark_l:
    mov al, 'L'
    jmp debug_emit

debug_segment_index:
    mov al, '0'
    add al, bl
    jmp debug_emit

debug_segment_done:
    mov al, 'A'
    add al, bl
    jmp debug_emit

debug_hex_nibble:
    and al, 0x0F
    cmp al, 10
    jb .digit
    add al, 'A' - 10
    jmp debug_emit
.digit:
    add al, '0'
    jmp debug_emit

debug_hex_byte:
    push ax
    shr al, 4
    call debug_hex_nibble
    pop ax
    call debug_hex_nibble
    ret

boot_drive:
    db 0
current_chunk_sectors:
    dw 0
current_dest:
    dd 0
current_lba:
    dd 0
current_file_size:
    dd 0
current_mem_size:
    dd 0
current_chunk_bytes:
    dd 0
kernel_entry_addr:
    dd 0
e820_continuation:
    dd 0
e820_tag_addr:
    dw 0
e820_entry_count:
    dw 0

disk_packet:
    db 0x10
    db 0
.sector_count:
    dw 0
.buffer_offset:
    dw 0
.buffer_segment:
    dw 0
.lba_low:
    dd 0
.lba_high:
    dd 0

align 8
gdt_start:
    dq 0x0000000000000000
    dq 0x00009A000000FFFF
    dq 0x00CF92000000FFFF
    dq 0x00CF9A000000FFFF
gdt_end:

gdt_descriptor:
    dw gdt_end - gdt_start - 1
    dd gdt_start
