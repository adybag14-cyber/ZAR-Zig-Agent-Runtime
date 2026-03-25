/* SPDX-License-Identifier: GPL-2.0-only */
.section .ap_trampoline,"ax"
.code16
.balign 4096

.global oc_i386_ap_trampoline_start
.type oc_i386_ap_trampoline_start,@function
oc_i386_ap_trampoline_start:
    cli
    cld
    movw %cs, %ax
    movw %ax, %ds
    movw %ax, %es
    movw %ax, %ss
    movw $(ap_trampoline_gdt_desc - oc_i386_ap_trampoline_start), %bx
    lgdt (%bx)
    movl %cr0, %eax
    orl $0x00000001, %eax
    movl %eax, %cr0
    ljmpl $0x08, $oc_i386_ap_trampoline_pmode

.code32
oc_i386_ap_trampoline_pmode:
    movw $0x10, %ax
    movw %ax, %ds
    movw %ax, %es
    movw %ax, %fs
    movw %ax, %gs
    movw %ax, %ss
    leal oc_i386_ap_shared_stack_top, %esp

    movl $1, oc_i386_ap_shared_stage
    incl oc_i386_ap_shared_startup_count

    movl oc_i386_ap_shared_local_apic_addr, %eax
    testl %eax, %eax
    jz ap_trampoline_no_lapic

    movl 0x20(%eax), %edx
    shrl $24, %edx
    movl %edx, oc_i386_ap_shared_reported_apic_id
    movl $1, oc_i386_ap_shared_started
    movl $4, oc_i386_ap_shared_stage
    movl $1, oc_i386_ap_shared_halted

ap_trampoline_halt:
    cli
    hlt
    jmp ap_trampoline_halt

ap_trampoline_no_lapic:
    movl $2, oc_i386_ap_shared_stage
    movl $1, oc_i386_ap_shared_halted
    jmp ap_trampoline_halt

.balign 8
ap_trampoline_gdt:
    .quad 0x0000000000000000
    .quad 0x00cf9a000000ffff
    .quad 0x00cf92000000ffff
ap_trampoline_gdt_end:

ap_trampoline_gdt_desc:
    .word ap_trampoline_gdt_end - ap_trampoline_gdt - 1
    .long ap_trampoline_gdt

.section .ap_trampoline_bss,"aw",@nobits
.balign 16
.global oc_i386_ap_shared_stage
oc_i386_ap_shared_stage:
    .long 0
.global oc_i386_ap_shared_started
oc_i386_ap_shared_started:
    .long 0
.global oc_i386_ap_shared_halted
oc_i386_ap_shared_halted:
    .long 0
.global oc_i386_ap_shared_startup_count
oc_i386_ap_shared_startup_count:
    .long 0
.global oc_i386_ap_shared_reported_apic_id
oc_i386_ap_shared_reported_apic_id:
    .long 0
.global oc_i386_ap_shared_target_apic_id
oc_i386_ap_shared_target_apic_id:
    .long 0
.global oc_i386_ap_shared_bsp_apic_id
oc_i386_ap_shared_bsp_apic_id:
    .long 0
.global oc_i386_ap_shared_local_apic_addr
oc_i386_ap_shared_local_apic_addr:
    .long 0

.balign 16
oc_i386_ap_shared_stack:
    .skip 4096
oc_i386_ap_shared_stack_top:

.global oc_i386_ap_trampoline_end
oc_i386_ap_trampoline_end:
