---
description: "Task list for uolt-head implementation"
---

# Tasks: uolt-head

**Prerequisites**: file-I/O primitives (open/read/close) + write/strlen (from uolt-cat).

**Tests**: INCLUDED (Principle XI).

## Phase 1: Research

- [x] T001 Confirm the reference header format is the shared GNU/BSD one:
        `==> name <==\n`, blank-line separator between sections, none before the first. Note the
        BSD/GNU divergences to steer clear of: BSD rejects the `-` operand and `-n 0`

## Phase 2: Tool

- [x] T002 [US2] `parse_uint` in `src/head/head.S`: lenient decimal parser (rdi -> rax),
        preserves rcx so it can run inside the option loop
- [x] T003 [US1/US2] Option scan: `-n number` / `-nnumber`, `--` end-of-options, default 10;
        leave r13 at the first operand and the operand count in rcx
- [x] T004 [US1] `head_fd`: read 64 KB blocks, scan for the Nth newline, emit the consumed
        prefix; whole-block emit + re-read when the block has fewer than N lines
- [x] T005 `emit`: drain a byte range to stdout, tolerating short writes; sets status on error
- [x] T006 [US3] `print_header`: `==> name <==` with a leading blank line except the first;
        `standard input` name for stdin; header printed only after a successful open
- [x] T007 [US3] Per-operand loop: stdin (`-`/none) vs open+head+close; open failure -> stderr
        diagnostic (no header) + status 1, continue
- [x] T008 Makefile: `EXTRA_head` (same set as cat) + append `head` to `TOOLNAMES`

## Phase 3: Tests

- [x] T009 [P] `tests/unit/head.sh`: default 10, `-n3`, `-n 2`, short file, no-newline tail,
        stdin, multi-file header layout, missing-then-good
- [x] T010 [P] `tests/posix/head.sh`: default, joined vs separate `-n`, `-n0`, stdin, `--`,
        binary-safe, nonzero on unreadable
- [x] T011 [P] `tests/differential/head.sh`: match reference `head` stdout+exit (default, `-n`
        forms, empty/no-newline, multi-file, missing, stdin); avoid `-` (BSD/GNU divergence)
- [x] T012 [P] `tests/fuzz/head.sh`: random contents and counts 1..24 match reference
- [x] T013 [P] `tests/trace/head.sh`: no mmap/brk; Linux shows read/write

## Phase 4: Polish

- [x] T014 Wire head tests into `make test`; add head size + timing to `bench/run.sh`
- [x] T015 Update `README.md` with the `uolt-head` row (size + system + speed)
- [x] T016 Verify macOS (`make test`) + Linux (`scripts/linux-test.sh`): all pass. Linux
        1336 B (< 2 KB), ~1.6× faster than /usr/bin/head; trace proves no heap

## Notes

- `-` = stdin and `-n 0` = empty output follow GNU; BSD diverges (rejects both), so differential
  and fuzz stay within the common denominator.
- More live values than callee-saved registers -> operand count and the header/first-output
  flags live in three rbp-relative stack locals; N and the argv walk stay in registers.
