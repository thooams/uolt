# Feature Specification: uolt-expr

**Feature Branch**: `034-uolt-expr` | **Date**: 2026-07-15 | **Status**: Implemented

## Summary

`expr EXPRESSION`: evaluate an expression and write its value to stdout. Exit 0 if the value is
neither null nor "0", 1 if it is null or "0", 2 on an invalid expression or a runtime error. Each
operator is a separate argv token (as the shell splits it). Precedence, lowest first: `|`, `&`,
the relational operators `< <= = != >= >`, `+ -`, `* / %`, then `( )` grouping; all
left-associative.

## Requirements
- FR-001: Integer arithmetic `+ - * / %` (64-bit, truncated toward zero); a non-integer operand or
  division/remainder by zero is a runtime error (exit 2).
- FR-002: Relational `< <= = != >= >` yielding "1"/"0" - numeric when both operands are integers,
  otherwise byte-lexical.
- FR-003: `|` returns its first operand when that is neither null nor "0", else the second; `&`
  returns the first when neither operand is null or "0", else "0".
- FR-004: `( expr )` grouping; a syntax error or missing operand is exit 2.
- FR-005: Exit 0/1 by whether the result value is non-null and not "0". No heap (Principle IV).
  README entry recorded.

## Success Criteria
- SC-001: stdout and exit code match the system expr for the operators both GNU and BSD agree on
  (see the differential test; stderr text is implementation-specific and not compared).
- SC-002: Binary < 3 KB on Linux (2104 B).

## Assumptions
- The `:` anchored-BRE match operator is deferred (documented) until a regex engine exists;
  arithmetic overflow is not detected (64-bit wraparound). Arithmetic results are formatted into a
  fixed 4 KB stack arena (no heap). Reuses write/strlen; no new syscall.
