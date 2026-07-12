/* uolt.ld - minimal Linux x86_64 link script (size-first).
 *
 * Default ld emits several page-aligned PT_LOAD segments (separate code), which
 * pads a tiny tool to several KB. We collapse everything into one segment that
 * starts immediately after the ELF + program headers (`. = SIZEOF_HEADERS`), so
 * the file is essentially headers + our handful of bytes of code. All unwind /
 * note / comment sections are discarded (Principle VI: justify every byte).
 */

ENTRY(_start)

SECTIONS
{
  . = SIZEOF_HEADERS;

  .text : {
    *(.text*)
    *(.rodata*)
    *(.data*)
    *(.bss*)
  }

  /DISCARD/ : {
    *(.comment)
    *(.note*)
    *(.eh_frame*)
    *(.eh_frame_hdr)
  }
}
