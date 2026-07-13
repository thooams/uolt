---
description: "Task list for uolt-tail implementation"
---

# Tasks: uolt-tail

**Prerequisites**: file-I/O primitives (open/read/close) + write/strlen (cat/head).

**Tests**: INCLUDED (Principle XI).

## Phase 1: Research

- [x] T001 Confirm the two required paths: regular files support `lseek(SEEK_END)` + backward
        scan; pipes return `-ESPIPE` and need a bounded sliding window (no heap). Note BSD/GNU
        agreement on `-n +N` and `-n 0` (both accepted) so those can be tested differentially

## Phase 2: Foundational

- [x] T002 [P] `sys/linux/lseek.S` (SYS_LSEEK 8), `sys/macos/lseek.S` (0x20000C7, carry ->
        negative)
- [x] T003 `libuolt/lseek.S`: uolt_lseek(fd, offset, whence)

## Phase 3: Tool

- [x] T004 [US2] Option scan in `src/tail/tail.S`: `-n number` / `-nnumber` / `-n +number`,
        `--`, default 10, plus flag; `parse_uint` (preserves rcx)
- [x] T005 [US1] `last_lines`: lseek to end, scan 64 KB blocks backwards counting newlines
        (skip one trailing newline), seek to the start, `copy_to_eof`; `-n 0` prints nothing
- [x] T006 [US3] `last_lines_pipe`: sliding window retaining the last 64 KB (buffer 2*64 KB,
        `rep movsb` compaction), then locate the last N lines and `emit`
- [x] T007 [US2] `forward_from_line`: skip to line N, emit the rest, `copy_to_eof`
- [x] T008 helpers `copy_to_eof` / `read_exact` / `emit` / `print_header`; per-operand loop with
        stdin (`-`/none), headers, and open-failure diagnostic (no header) + status 1
- [x] T009 Makefile: `EXTRA_tail` (adds lseek) + append `tail` to `TOOLNAMES`

## Phase 4: Tests

- [x] T010 [P] `tests/unit/tail.sh`: default, `-n3`, `-n +10`, short/no-newline, stdin, multi
        headers, missing-then-good
- [x] T011 [P] `tests/posix/tail.sh`: joined/separate `-n`, `+N` joined/separate, `-n0`, stdin,
        `--`, binary-safe, nonzero on unreadable
- [x] T012 [P] `tests/differential/tail.sh`: match reference `tail` stdout+exit (default, `-n`
        forms, `+N`, `-n0`, empty/no-newline, multi-file, missing, stdin)
- [x] T013 [P] `tests/fuzz/tail.sh`: random contents/counts on both file and pipe paths
- [x] T014 [P] `tests/trace/tail.sh`: no mmap/brk; Linux shows read/write and lseek

## Phase 5: Polish

- [x] T015 Wire tail tests into `make test`; add tail size + big-file timing to `bench/run.sh`
- [x] T016 Update `README.md` with the `uolt-tail` row
- [x] T017 Verify macOS + Linux: all pass. Linux 1976 B (< 2 KB), ~1.1× (parity) on a 38 MB
        file via backward seek; trace proves no heap and shows lseek

## Notes

- Bug found in bring-up: the backward scan kept its newline count / first-byte flag in r8/r9,
  but `read_exact` clobbers those caller-saved regs -> whole file was emitted. Moved the scan
  state to rbp stack locals (LOC_CNT/LOC_FB/LOC_CS).
- `-n 0` needed an explicit early return in both paths (count could never reach 0 by the loop).
- Pipe path caps output at the last 64 KB of the requested tail (documented no-heap limit).
