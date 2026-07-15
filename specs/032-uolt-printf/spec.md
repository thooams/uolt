# Feature Specification: uolt-printf

**Feature Branch**: `032-uolt-printf` | **Date**: 2026-07-15 | **Status**: Implemented

## Summary

`printf format [argument...]`: write the arguments under the control of the format string, like
the C printf and the POSIX `printf` utility. The format is reused (cycled) while unconsumed
arguments remain and the previous pass consumed at least one argument. The format string supports
backslash escapes (`\\ \a \b \f \n \r \t \v \"` and `\ddd` octal) and conversion specifications
with flags (`-` `+` space `#` `0`), a field width, and a precision.

## Requirements
- FR-001: Conversions `%d %i %u %o %x %X %c %s %b %%`, with flags, decimal width, and decimal
  precision applied per C/POSIX semantics.
- FR-002: Format-string backslash escapes and `%b` argument escapes (including `\c`, which stops
  all further output).
- FR-003: Numeric arguments parse as C integer constants (optional sign, `0x` hex / `0` octal /
  decimal); a leading `'` or `"` yields the next byte's value. A missing argument is the empty
  string for `%s`/`%c` and zero for the numeric conversions.
- FR-004: Argument cycling; no format operand is an error (exit 1); an unknown conversion is an
  error (exit 1). No heap (Principle IV).
- FR-005: README entry recorded.

## Success Criteria
- SC-001: Output matches the system printf byte-for-byte for the POSIX conversions both GNU and
  BSD agree on (see the differential test).
- SC-002: Binary < 3 KB on Linux (2720 B; macOS ~9.7 KB floor).

## Assumptions
- The floating conversions (`%e %E %f %g %G %a %A`) and the dynamic `*` width/precision are
  deferred (documented limitation, same spirit as `seq` deferring floats). Field width, precision,
  and a `%b` result are each bounded (no heap): width/precision cap at 256, `%b` at 4096 bytes.
- `%c` on a *missing* argument is impl-defined (GNU emits a NUL, BSD nothing); covered only by the
  unit test. Trailing junk after a numeric argument is ignored (no "not completely converted"
  diagnostic), so the differential test uses clean numeric arguments. Reuses write/strlen.
