---
description: "Task list for uolt-printf implementation"
---
# Tasks: uolt-printf
- [x] T001 src/printf/printf.S: format walk + buffered output (ob_put/ob_putc/ob_flush)
- [x] T002 Escapes: do_escape (format string) + named_esc + octal; `%b` expansion with `\c` stop
- [x] T003 Conversion spec parse: flags (`- + space # 0`), width, precision, dispatch
- [x] T004 Numbers: parse_num (sign, 0x/0/dec, `'c` byte value) + conv_num (sign, prec, `#`, padding)
- [x] T005 Strings/char: emit_str + emit_pad (width, precision, FLAG_MINUS); argument cycling
- [x] T006 Makefile: EXTRA_printf + TOOLNAMES
- [x] T007 tests/unit/printf.sh + tests/differential/printf.sh
- [x] T008 README row; verify macOS + Linux (2720 B)

## Notes
- Stack locals start below -40: the prologue pushes five callee-saved registers (rbx, r12-r15)
  into [rbp-8 .. rbp-40], so overlapping locals there would corrupt the restored registers (the
  same latent trap seq/put_num skirts by writing a dead slot).
- Helpers keep live state in stack locals and touch only caller-saved scratch, so the callee-saved
  registers holding the format walk (r12/r13) and conv_num's dptr/plen/dlen (r8/r9/r10) survive
  every call; only the flush path reloads rdi/rsi/rdx.
- `%c` on a missing argument diverges GNU (NUL) vs BSD (nothing) -> unit test only. Trailing junk
  after a numeric argument is ignored -> differential uses clean numeric arguments.
