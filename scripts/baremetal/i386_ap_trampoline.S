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

    movl oc_i386_ap_shared_boot_slot_index, %esi
    cmpl $3, %esi
    jbe ap_trampoline_slot_ready
    xorl %esi, %esi

ap_trampoline_slot_ready:
    movl %esi, %eax
    shll $12, %eax
    leal oc_i386_ap_shared_stacks(%eax), %esp
    addl $4096, %esp

    movl $1, oc_i386_ap_slot_stage(,%esi,4)
    incl oc_i386_ap_slot_startup_count(,%esi,4)

    movl oc_i386_ap_slot_local_apic_addr(,%esi,4), %eax
    testl %eax, %eax
    jz ap_trampoline_no_lapic

    movl 0x20(%eax), %edx
    shrl $24, %edx
    movl %edx, oc_i386_ap_slot_reported_apic_id(,%esi,4)
    movl $1, oc_i386_ap_slot_started(,%esi,4)
    movl $4, oc_i386_ap_slot_stage(,%esi,4)
    xorl %edi, %edi

ap_trampoline_command_loop:
    incl oc_i386_ap_slot_heartbeat(,%esi,4)
    movl oc_i386_ap_slot_command_seq(,%esi,4), %eax
    cmpl %edi, %eax
    je ap_trampoline_pause
    movl %eax, %edi
    movl oc_i386_ap_slot_command_kind(,%esi,4), %ecx
    cmpl $1, %ecx
    je ap_trampoline_ping
    cmpl $2, %ecx
    je ap_trampoline_halt_command
    cmpl $3, %ecx
    je ap_trampoline_work
    cmpl $4, %ecx
    je ap_trampoline_batch_work
    movl %edi, oc_i386_ap_slot_response_seq(,%esi,4)
    jmp ap_trampoline_pause

ap_trampoline_ping:
    incl oc_i386_ap_slot_ping_count(,%esi,4)
    movl $5, oc_i386_ap_slot_stage(,%esi,4)
    movl %edi, oc_i386_ap_slot_response_seq(,%esi,4)
    jmp ap_trampoline_pause

ap_trampoline_halt_command:
    movl $6, oc_i386_ap_slot_stage(,%esi,4)
    movl %edi, oc_i386_ap_slot_response_seq(,%esi,4)
    movl $1, oc_i386_ap_slot_halted(,%esi,4)
    jmp ap_trampoline_halt

ap_trampoline_work:
    movl oc_i386_ap_slot_command_value(,%esi,4), %eax
    movl %eax, oc_i386_ap_slot_last_work_value(,%esi,4)
    addl %eax, oc_i386_ap_slot_work_accumulator(,%esi,4)
    incl oc_i386_ap_slot_work_count(,%esi,4)
    movl $7, oc_i386_ap_slot_stage(,%esi,4)
    movl %edi, oc_i386_ap_slot_response_seq(,%esi,4)
    jmp ap_trampoline_pause

ap_trampoline_batch_work:
    movl oc_i386_ap_slot_task_count(,%esi,4), %ecx
    testl %ecx, %ecx
    jz ap_trampoline_batch_work_empty
    cmpl $8, %ecx
    jbe ap_trampoline_batch_work_count_ready
    movl $8, %ecx

ap_trampoline_batch_work_count_ready:
    movl %esi, %ebp
    shll $5, %ebp
    xorl %eax, %eax
    xorl %ebx, %ebx

ap_trampoline_batch_work_loop:
    addl oc_i386_ap_slot_task_values(%ebp,%ebx,4), %eax
    incl %ebx
    cmpl %ecx, %ebx
    jne ap_trampoline_batch_work_loop
    jmp ap_trampoline_batch_work_commit

ap_trampoline_batch_work_empty:
    xorl %eax, %eax

ap_trampoline_batch_work_commit:
    movl %ecx, oc_i386_ap_slot_last_batch_count(,%esi,4)
    movl %eax, oc_i386_ap_slot_last_batch_accumulator(,%esi,4)
    incl oc_i386_ap_slot_batch_count(,%esi,4)
    movl $8, oc_i386_ap_slot_stage(,%esi,4)
    movl %edi, oc_i386_ap_slot_response_seq(,%esi,4)
    jmp ap_trampoline_pause

ap_trampoline_pause:
    pause
    jmp ap_trampoline_command_loop

ap_trampoline_halt:
    cli
    hlt
    jmp ap_trampoline_halt

ap_trampoline_no_lapic:
    movl $2, oc_i386_ap_slot_stage(,%esi,4)
    movl $1, oc_i386_ap_slot_halted(,%esi,4)
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
.global oc_i386_ap_shared_boot_slot_index
oc_i386_ap_shared_boot_slot_index:
    .long 0
.global oc_i386_ap_slot_stage
oc_i386_ap_slot_stage:
    .fill 4,4,0
.global oc_i386_ap_slot_started
oc_i386_ap_slot_started:
    .fill 4,4,0
.global oc_i386_ap_slot_halted
oc_i386_ap_slot_halted:
    .fill 4,4,0
.global oc_i386_ap_slot_startup_count
oc_i386_ap_slot_startup_count:
    .fill 4,4,0
.global oc_i386_ap_slot_reported_apic_id
oc_i386_ap_slot_reported_apic_id:
    .fill 4,4,0
.global oc_i386_ap_slot_target_apic_id
oc_i386_ap_slot_target_apic_id:
    .fill 4,4,0
.global oc_i386_ap_slot_bsp_apic_id
oc_i386_ap_slot_bsp_apic_id:
    .fill 4,4,0
.global oc_i386_ap_slot_local_apic_addr
oc_i386_ap_slot_local_apic_addr:
    .fill 4,4,0
.global oc_i386_ap_slot_command_kind
oc_i386_ap_slot_command_kind:
    .fill 4,4,0
.global oc_i386_ap_slot_command_value
oc_i386_ap_slot_command_value:
    .fill 4,4,0
.global oc_i386_ap_slot_command_seq
oc_i386_ap_slot_command_seq:
    .fill 4,4,0
.global oc_i386_ap_slot_response_seq
oc_i386_ap_slot_response_seq:
    .fill 4,4,0
.global oc_i386_ap_slot_heartbeat
oc_i386_ap_slot_heartbeat:
    .fill 4,4,0
.global oc_i386_ap_slot_ping_count
oc_i386_ap_slot_ping_count:
    .fill 4,4,0
.global oc_i386_ap_slot_work_count
oc_i386_ap_slot_work_count:
    .fill 4,4,0
.global oc_i386_ap_slot_last_work_value
oc_i386_ap_slot_last_work_value:
    .fill 4,4,0
.global oc_i386_ap_slot_work_accumulator
oc_i386_ap_slot_work_accumulator:
    .fill 4,4,0
.global oc_i386_ap_slot_task_count
oc_i386_ap_slot_task_count:
    .fill 4,4,0
.global oc_i386_ap_slot_task_values
oc_i386_ap_slot_task_values:
    .fill 32,4,0
.global oc_i386_ap_slot_batch_count
oc_i386_ap_slot_batch_count:
    .fill 4,4,0
.global oc_i386_ap_slot_last_batch_count
oc_i386_ap_slot_last_batch_count:
    .fill 4,4,0
.global oc_i386_ap_slot_last_batch_accumulator
oc_i386_ap_slot_last_batch_accumulator:
    .fill 4,4,0

.balign 16
.global oc_i386_ap_shared_stacks
oc_i386_ap_shared_stacks:
    .skip 16384

.global oc_i386_ap_trampoline_end
oc_i386_ap_trampoline_end:
