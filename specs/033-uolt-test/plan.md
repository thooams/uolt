# Implementation Plan: uolt-test

**Branch**: `main` (spec dir `033-uolt-test`) | **Date**: 2026-07-15

Detect the `[` invocation from argv[0]'s basename and, if so, require and strip a trailing `]`.
Dispatch on the operand count: 0 -> false; 1 -> one_argument (non-empty string); 2/3/4 ->
two_args/three_args/four_args, which encode the POSIX corner cases (`! S`, unary op, binary op,
`( x )`, negation); five or more -> general_eval, a recursive-descent grammar or_expr (`-o`) >
and_expr (`-a`) > factor (`!`, `( )`) > primary. A primary consumes 3 tokens (`a OP b`), 2 (`UNOP
a`), or 1 (a string). apply_binop parses integers (test_atoi) for `-eq..-le` or compares strings
for `=`/`!=`; apply_unop runs the string/stat/access checks. A syntax error longjmps to the exit
epilogue via rbp (resetting rsp), prints to stderr, and exits 2.

## Constitution Check
All PASS: pure assembly; stat/lstat/access/write direct via uolt_* wrappers; static Linux /
libSystem-stub macOS; no heap (fixed stack locals; the stat/access syscalls own their scratch);
2592 B (measured); documented (`-t` and GNU `<`/`>` deferred); unit + differential on both OSes.

## Structure
- src/test/test.S: bracket detection; count dispatch (one/two/three/four_args); recursive grammar
  (or_expr/and_expr/factor/primary); apply_unop/apply_binop; is_unop/is_binop; test_streq/test_atoi
- sys/<os>/{access,lstatmode,statsize}.S + libuolt/{access,lstatmode,statsize}.S (new wrappers)
- tests/{unit,differential}/test.sh (the `[` alias tested through a symlink)
