/* uolt.ld - minimal Linux x86_64 link script (size-first).
 *
 * Default ld emits several page-aligned PT_LOAD segments (separate code), which
 * pads a tiny tool to several KB. We collapse everything into ONE executable
 * PT_LOAD segment that also covers the ELF header and program headers
 * (FILEHDR PHDRS), so the file is essentially headers + our handful of bytes of
 * code. Unwind / note / comment sections are discarded (Principle VI).
 *
 * The segment must be executable (FLAGS(5) = R+X) and loaded at the conventional
 * static base 0x400000; otherwise the kernel maps a non-exec / low page and
 * _start faults (SIGSEGV). The header bytes are consumed by SIZEOF_HEADERS so
 * the entry lands right after them.
 */

ENTRY(_start)

PHDRS
{
  text PT_LOAD FILEHDR PHDRS FLAGS(5);   /* one R+X segment, includes headers */
}

SECTIONS
{
  . = 0x400000 + SIZEOF_HEADERS;

  .text : {
    *(.text*)
    *(.rodata*)
    *(.data*)
  } :text

  /DISCARD/ : {
    *(.comment)
    *(.note*)
    *(.eh_frame*)
    *(.eh_frame_hdr)
    *(.bss*)
  }
}
