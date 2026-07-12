---
description: "Task list for uolt-cat implementation"
---

# Tasks: uolt-cat

**Prerequisites**: entry shim + libuolt write/strlen (from uolt-echo/uolt-pwd).

**Tests**: INCLUDED (Principle XI).

## Phase 1: Research

- [x] T001 Confirm the file-I/O syscall path per OS: Linux open(2)/read(0)/close(3) return
        -errno on error; macOS BSD class 0x2000000|{5,3,6} signal errors via the carry flag
        with errno in rax - normalize to a negative return for uniform sign checks

## Phase 2: Foundational

- [x] T002 [P] `sys/linux/open.S`, `sys/linux/read.S`, `sys/linux/close.S`: syscall wrappers
- [x] T003 [P] `sys/macos/open.S`, `sys/macos/read.S`, `sys/macos/close.S`: same, with
        carry-flag -> negative normalization on open/read
- [x] T004 [P] `libuolt/open.S`, `libuolt/read.S`, `libuolt/close.S`: uolt_* tail calls

## Phase 3: Tool

- [x] T005 [US1/US2/US3] `src/cat/cat.S`: skip a `-u` option; per operand, copy stdin (no
        operand or `-`) or open+copy+close a file through a 64 KB stack buffer; drain each read
        chunk fully to stdout; on open failure emit a stderr diagnostic and set status 1
- [x] T006 Makefile: `EXTRA_cat` + append `cat` to `TOOLNAMES`

## Phase 4: Tests

- [x] T007 [P] `tests/unit/cat.sh`: single/multi/empty files, stdin, `-`, missing-then-good
- [x] T008 [P] `tests/posix/cat.sh`: verbatim, order, stdin, `-u` no-op, binary-safe, nonzero
        on unreadable
- [x] T009 [P] `tests/differential/cat.sh`: match `/bin/cat` stdout + exit (files, stdin, `-`,
        big/binary, missing); stderr text intentionally not compared
- [x] T010 [P] `tests/fuzz/cat.sh`: random file contents/counts match reference byte-for-byte
- [x] T011 [P] `tests/trace/cat.sh`: no mmap/brk; Linux shows read/write

## Phase 5: Polish

- [x] T012 Wire cat tests into `make test`; add cat size + timing to `bench/run.sh`
- [x] T013 Update `README.md` with the `uolt-cat` row (size + system + speed)
- [x] T014 Verify macOS (`make test`) + Linux (`scripts/linux-test.sh`): all pass. Linux
        824 B (< 2 KB), ~1.7× faster than /usr/bin/cat; trace/cat proves no heap

## Notes

- Bug found during bring-up: `mov rdx, (. - err_pre)` assembled as a memory load, not an
  immediate (GAS Intel syntax treats a location-difference symbol as an address). Fixed by
  making the diagnostic strings NUL-terminated and measuring length with strlen (no magic
  numbers), via a small `err_puts` helper.
- `-u` is the only POSIX option and is a no-op here (direct writes are already unbuffered).
  Other `-x` tokens are treated as filenames (open fails -> diagnostic + nonzero exit).
