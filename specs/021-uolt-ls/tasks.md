---
description: "Task list for uolt-ls implementation"
---

# Tasks: uolt-ls

**Prerequisites**: write + strlen + close.

**Tests**: INCLUDED (Principle XI).

## Phase 1: Research

- [x] T001 Determine the directory-read path per OS: Linux getdents64 (217); macOS
        getdirentries64 (344), which takes a 4th position argument. Verify macOS is NOT gated
        (unlike getcwd/nanosleep) - it works as a direct syscall. Note the dirent layouts
        (d_reclen at 16 both; d_name at 19 Linux / 21 macOS)

## Phase 2: Foundational

- [x] T002 `include/uolt.inc`: DIRENT_RECLEN_OFF / DIRENT_NAME_OFF selected by -DUOLT_OS_*
- [x] T003 Makefile: pass `-DUOLT_OS_LINUX` / `-DUOLT_OS_MACOS` (OSDEF) to the assembler
- [x] T004 [P] `sys/{linux,macos}/getdents.S` (217 / 344 with position); `libuolt/getdents.S`
- [x] T005 [P] `sys/{linux,macos}/opendir.S` (open O_DIRECTORY 0x10000 / 0x100000);
        `libuolt/opendir.S`

## Phase 3: Tool

- [x] T006 [US1/US3] `src/ls/ls.S`: option scan (-a/-1, --); per operand opendir (ENOTDIR ->
        print file name, ENOENT/other -> diagnostic); read the directory in 32 KB batches and
        print each entry name (skip hidden unless -a); no operand lists "."
- [x] T007 Makefile: `EXTRA_ls` + append `ls` to `TOOLNAMES`

## Phase 4: Tests

- [x] T008 [P] `tests/unit/ls.sh`: default/-a/named-dir/file/path/empty/missing (sorted-set)
- [x] T009 [P] `tests/differential/ls.sh`: name set matches `ls -1` (sorted) for one operand
- [x] T010 [P] `tests/trace/ls.sh`: getdents observed, no mmap/brk

## Phase 5: Polish

- [x] T011 Wire ls tests into `make test`
- [x] T012 Update `README.md` with the `uolt-ls` row
- [x] T013 Verify macOS + Linux: all pass. Linux 976 B (< 1 KB)

## Notes

- Bring-up bug: reading a *file* fd with getdirentries64 on macOS looped forever (the fd offset
  did not advance). Fixed by opening with O_DIRECTORY, so non-directories fail at open (ENOTDIR)
  and never reach the read loop; also added a reclen==0 guard as a safety net.
- Output is unsorted (v1); differential compares sorted sets. Sorting, columns, -l, and
  multi-operand headers are deferred.
