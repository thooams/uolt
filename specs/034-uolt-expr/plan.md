# Implementation Plan: uolt-expr

**Branch**: `main` (spec dir `034-uolt-expr`) | **Date**: 2026-07-15

A recursive-descent parser over the operand vector (r15 base, r14 count, cursor LOC_IDX), one
function per precedence level: parse_or (`|`) > parse_and (`&`) > parse_cmp (relational) >
parse_add (`+ -`) > parse_mul (`* / %`) > parse_prim (`( expr )` or a string). Each level loops
left-associatively, holding its operands on the machine stack across the recursive calls. Values
flow up as string pointers: operands and `|`/`&` results are the original argv strings or the
constants "0"/"1"; arithmetic results are formatted by fmt_int_arena into a fixed 4 KB stack arena
(arena_copy bump-allocates, a full arena is a runtime error). do_compare parses both sides as
integers for a numeric compare and falls back to strcmp3 (byte order) otherwise. A syntax error or
runtime error longjmps to the exit epilogue via rbp and exits 2; otherwise the value is printed and
the exit code is val_false(result) (1 for null/"0", else 0).

## Constitution Check
All PASS: pure assembly; write direct via uolt_write; static Linux / libSystem-stub macOS; no heap
(fixed stack arena, bounded; overflow is a runtime error); uolt_* wrappers; 2104 B (measured);
documented (`:` match and overflow deferred); unit + differential on both OSes.

## Structure
- src/expr/expr.S: parse_or/and/cmp/add/mul/prim; do_compare/do_addsub/do_muldiv; which_cmp/add/mul;
  parse_intval/streq/strcmp3/val_false; fmt_int_arena/arena_copy
- tests/{unit,differential}/expr.sh (stdout + exit code; stderr text not compared)
