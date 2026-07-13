---
description: "Task list for uolt-wc implementation"
---

# Tasks: uolt-wc

**Prerequisites**: file-I/O primitives (open/read/close) + write/strlen (cat/head/tail).

**Tests**: INCLUDED (Principle XI).

## Phase 1: Research

- [x] T001 Confirm the output format is implementation-defined and differs between GNU (dynamic
        width) and BSD (fixed %8d); decide on single-space, no-padding output and compare counts
        after whitespace normalization. Fix the count semantics as byte-based C locale (matches
        `wc` under LC_ALL=C and is much faster than the default multibyte pass)

## Phase 2: Tool

- [x] T002 [US2] Option scan in `src/wc/wc.S`: `-l`/`-w`/`-c`, combined (`-lwc`), separate,
        `--`; build a show mask; default to all three when none given
- [x] T003 [US1] `count_fd`: one byte-at-a-time pass over 64 KB blocks counting newlines, words
        (in-word flag over the C-locale blank set), and bytes; counts survive syscalls in r8-r10
- [x] T004 `put_uint` (divide into a 20-byte scratch), `put_str`, `put_char`, `sep_if_needed`,
        and `emit_line` printing enabled columns in the fixed order lines, words, bytes + name
- [x] T005 [US3] Per-operand loop: stdin when no operand (no name), open+count+close per file,
        running totals, a `total` line for >1 operand, open-failure diagnostic + status 1
- [x] T006 Makefile: `EXTRA_wc` (same set as cat) + append `wc` to `TOOLNAMES`

## Phase 3: Tests

- [x] T007 [P] `tests/unit/wc.sh`: counts, per-flag, no-newline, empty, stdin, multi + total,
        missing-then-good
- [x] T008 [P] `tests/posix/wc.sh`: fixed output order, combined vs separate flags, `--`,
        tab/space words, NUL byte count, nonzero on unreadable
- [x] T009 [P] `tests/differential/wc.sh`: match reference `wc` (LC_ALL=C) counts + exit,
        whitespace-normalized (default, flags, empty, no-newline, tabs, big, multi, missing, stdin)
- [x] T010 [P] `tests/fuzz/wc.sh`: random text over the four option variants matches reference
- [x] T011 [P] `tests/trace/wc.sh`: no mmap/brk; Linux shows read/write

## Phase 4: Polish

- [x] T012 Wire wc tests into `make test`; add wc size + big-file timing to `bench/run.sh`
- [x] T013 Update `README.md` with the `uolt-wc` row (+ the C-locale speedup caveat)
- [x] T014 Verify macOS + Linux: all pass. Linux 1368 B (< 2 KB), ~11× faster than the stock wc
        on ~50 MB; trace proves no heap

## Notes

- Output spacing is implementation-defined; differential normalizes whitespace and compares
  counts + name, with the reference under LC_ALL=C for byte-based agreement.
- `-m` (characters) and the `-` stdin alias are deferred.
