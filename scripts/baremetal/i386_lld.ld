ENTRY(multiboot32_start)
PHDRS
{
  note PT_NOTE FLAGS(4);
  apboot PT_LOAD FLAGS(5);
  apdata PT_LOAD FLAGS(6);
  text PT_LOAD FLAGS(5);
  data PT_LOAD FLAGS(6);
}
SECTIONS
{
  . = 0x00080000;

  .ap_trampoline ALIGN(4096) : {
    KEEP(*(.ap_trampoline))
  } :apboot

  .ap_trampoline_bss ALIGN(16) (NOLOAD) : {
    KEEP(*(.ap_trampoline_bss))
  } :apdata

  . = 0x00100000;

  .note.Xen ALIGN(4) : {
    KEEP(*(.note.Xen))
  } :note

  .multiboot ALIGN(8) : {
    KEEP(*(.multiboot))
  } :text

  .text ALIGN(16) : {
    *(.text.boot)
    *(.text .text.*)
  } :text

  .rodata ALIGN(16) : {
    *(.rodata .rodata.*)
    *(.eh_frame .eh_frame.*)
    *(.eh_frame_hdr)
  } :text

  .data ALIGN(16) : {
    *(.data .data.*)
    *(.data.rel.ro .data.rel.ro.*)
  } :data

  .bss ALIGN(4096) : {
    *(.bss.boot)
    *(.bss .bss.* COMMON)
  } :data

  /DISCARD/ : {
    *(.debug*)
    *(.comment)
    *(.note.GNU-stack)
  }
}
