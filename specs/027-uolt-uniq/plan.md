# Implementation Plan: uolt-uniq

**Branch**: `main` (spec dir `027-uolt-uniq`) | **Date**: 2026-07-14

Collapse adjacent duplicate lines with -c/-d/-u. Reuses the block-read line splitter (from grep);
`take_line` compares each line with the run held in a separate prev buffer, extending or flushing
it; `flush_run` applies the -d/-u filter and the -c count prefix. No new syscall.

## Constitution Check
All PASS: pure assembly; open/read/close/write direct; static/stub; no heap (2x64 KB stack
buffers); uolt_* wrappers; 1248 B; measured; POSIX subset; documented; unit+differential(+fuzz).

## Structure
- src/uniq/uniq.S: option scan; line loop; take_line (run compare/copy); flush_run; put_count
- tests/{unit,differential}/uniq.sh
