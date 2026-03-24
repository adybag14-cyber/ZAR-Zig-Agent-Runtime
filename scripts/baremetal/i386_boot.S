/* SPDX-License-Identifier: GPL-2.0-only */
.section .note.Xen,"a",@note
.balign 4
.long 4
.long 4
.long 18
.asciz "Xen"
.balign 4
.long pvh_i386_start
.balign 4

.section .text.boot,"ax"
.code32
.balign 8

.global multiboot32_start
.type multiboot32_start,@function
multiboot32_start:
    jmp pvh_i386_start

.global pvh_i386_start
.type pvh_i386_start,@function
pvh_i386_start:
    cli
    cld
    movl $stack32_top, %esp
    andl $-16, %esp

    # Enable x87/SSE before entering Zig runtime.
    # Clear CR0.EM/CR0.TS and set CR0.MP/CR0.NE.
    movl %cr0, %eax
    andl $~(0x00000004), %eax
    andl $~(0x00000008), %eax
    orl  $0x00000022, %eax
    movl %eax, %cr0

    # Set CR4.OSFXSR and CR4.OSXMMEXCPT for XMM instructions.
    movl %cr4, %eax
    orl  $0x00000600, %eax
    movl %eax, %cr4

    fninit
    call _start

1:
    hlt
    jmp 1b

.section .bss.boot,"aw",@nobits
.balign 16
stack32:
    .skip 131072
stack32_top:
