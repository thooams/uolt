---
description: "Task list for uolt-expr implementation"
---
# Tasks: uolt-expr
- [x] T001 src/expr/expr.S: recursive-descent levels parse_or/and/cmp/add/mul/prim over the cursor
- [x] T002 Operator work: do_compare (numeric or strcmp3), do_addsub, do_muldiv (div/mod-by-zero err)
- [x] T003 Recognizers which_cmp/which_add/which_mul; helpers streq/strcmp3/parse_intval/val_false
- [x] T004 Arithmetic result formatting: fmt_int_arena + arena_copy (fixed 4 KB stack arena)
- [x] T005 Value print + exit status (val_false); error longjmp to the rbp epilogue (exit 2)
- [x] T006 Makefile: EXTRA_expr + TOOLNAMES
- [x] T007 tests/unit/expr.sh + tests/differential/expr.sh (stdout + exit; stderr not compared)
- [x] T008 README row; verify macOS + Linux (2104 B)

## Notes
- Completes the scripting trio (printf, test, expr). expr needs no new syscall.
- Each precedence level keeps its operands (and the operator code) on the machine stack across the
  recursive call, so recursion is re-entrant without shared locals; only LOC_IDX and the arena bump
  are frame-global. Same stack-locals-below-40 rule as printf/test.
- The `:` BRE match operator is deferred (needs a regex engine); a `:` token therefore falls through
  as an unconsumed operand and yields a syntax error. Overflow is not detected (64-bit wraparound).
- Differential compares stdout + exit code only; the stderr diagnostic text differs GNU vs BSD.
