# Implementation Plan: uolt-printf

**Branch**: `main` (spec dir `032-uolt-printf`) | **Date**: 2026-07-15

Walk the format string one byte at a time: ordinary bytes and backslash escapes go straight to a
4 KB output buffer (OBUF); a `%` starts a conversion spec, parsed as flags -> width -> precision ->
conversion char. Each conversion pulls the next argument (next_arg, which returns the empty string
and stops advancing once arguments run out, so cycling terminates). Numbers are parsed by parse_num
and formatted by conv_num (digits built downward in a bounded buffer, then precision zeros, `#`
prefix, sign, and zero/space width padding); strings and `%b` go through emit_str. `%b` expands the
argument's escapes into a bounded buffer, honoring `\c` (flush + exit). All output funnels through
OBUF for exact ordering and batched syscalls; it is flushed once at the end. No new syscall.

## Constitution Check
All PASS: pure assembly; write direct via uolt_write; static Linux / libSystem-stub macOS; no heap
(OBUF 4 KB + %b buffer 4 KB + a bounded number buffer, all on the stack; width/precision capped);
uolt_* wrappers; 2720 B (measured); documented (floats + `*` deferred); unit + differential on both
OSes.

## Structure
- src/printf/printf.S: format walk; do_escape/named_esc; conv spec parse; conv_num/parse_num;
  emit_str/emit_pad; ob_put/ob_putc/ob_flush; next_arg; err_puts
- tests/{unit,differential}/printf.sh
