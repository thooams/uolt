---
description: "Task list for uolt-sleep implementation"
---

# Tasks: uolt-sleep

**Prerequisites**: write + strlen (diagnostics).

**Tests**: INCLUDED (Principle XI).

## Phase 1: Research

- [x] T001 Discover macOS has no direct `nanosleep` syscall (absent from the SDK syscall.h; libc
        uses `__semwait_signal`). Choose `select` for macOS and `nanosleep` for Linux, behind one
        `uolt_sleep(sec, nsec)`

## Phase 2: Foundational

- [x] T002 [P] `sys/linux/sleep.S`: nanosleep(35) with an -EINTR resume loop
- [x] T003 [P] `sys/macos/sleep.S`: select(0x200005D) with a timeval, EINTR retry
- [x] T004 `libuolt/sleep.S`: uolt_sleep(sec, nsec)

## Phase 3: Tool

- [x] T005 [US1/US2] `src/sleep/sleep.S`: `parse_dur` (integer + fraction + s/m/h/d suffix),
        sum operands in nanoseconds, split to sec/nsec, call uolt_sleep; error on bad/missing
- [x] T006 Makefile: `EXTRA_sleep` (adds the sleep primitive) + append `sleep` to `TOOLNAMES`

## Phase 4: Tests

- [x] T007 [P] `tests/unit/sleep.sh`: timing bands for integer/fraction/sum/suffix, error exits
- [x] T008 [P] `tests/posix/sleep.sh`: integer-seconds wait, non-numeric error
- [x] T009 [P] `tests/trace/sleep.sh`: nanosleep observed (Linux), no mmap/brk

## Phase 5: Polish

- [x] T010 Wire sleep tests into `make test`
- [x] T011 Update `README.md` with the `uolt-sleep` row
- [x] T012 Verify macOS + Linux: all pass. Linux 960 B (< 1 KB); macOS sleeps via select

## Notes

- First attempt used a `nanosleep` syscall wrapper with number 240 on macOS: it returned
  immediately (no such syscall). Replaced with the `select` approach.
- Test gotcha: a timing helper that ends in `awk` masks the tool's exit code in `$?`; capture the
  tool's status directly, separately from the timing.
