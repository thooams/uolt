# Feature Specification: uolt-test

**Feature Branch**: `033-uolt-test` | **Date**: 2026-07-15 | **Status**: Implemented

## Summary

`test expression` / `[ expression ]`: evaluate a conditional expression and exit 0 (true), 1
(false), or 2 (syntax error). When invoked as `[` (via a symlink), the final argument must be `]`
and is stripped before evaluation. Evaluation follows the POSIX argument-count algorithm for 0-4
arguments and a recursive-descent grammar (`-o` < `-a` < `!` < `( )`) for five or more.

## Requirements
- FR-001: String primaries `-n S`, `-z S`, `S1 = S2`, `S1 != S2`, and the one-argument form (true
  if the string is non-empty).
- FR-002: Integer primaries `n1 -eq|-ne|-gt|-ge|-lt|-le n2`; a non-integer operand is a syntax
  error (exit 2).
- FR-003: File primaries `-e -f -d -s -r -w -x -h -L -p -S -b -c -g -u -k FILE` (stat/lstat/access).
- FR-004: Operators `! expr`, `expr1 -a expr2`, `expr1 -o expr2`, and `( expr )` grouping.
- FR-005: The `[` invocation requires a trailing `]`; missing it is a syntax error. No heap
  (Principle IV). README entry recorded.

## Success Criteria
- SC-001: Exit codes match the system test (and `[`) for the POSIX primaries both GNU and BSD
  agree on (see the differential test).
- SC-002: Binary < 3 KB on Linux (2592 B; macOS Mach-O floor is larger).

## Assumptions
- `-t FD` is deferred (it needs a terminal ioctl, a different mechanism than the stat/access
  primaries) and so are the GNU string `<` / `>` comparisons. New syscall wrappers: access(2),
  lstat (st_mode), and stat (st_size); the existing statmode covers the follow-symlink file-type
  and permission-bit tests. Reuses write/strlen.
