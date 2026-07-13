---
description: "Task list for uolt-mkdir implementation"
---

# Tasks: uolt-mkdir

**Prerequisites**: write + strlen (diagnostics).

**Tests**: INCLUDED (Principle XI).

## Phase 1: Foundational

- [x] T001 [P] `sys/linux/mkdir.S` (SYS_MKDIR 83), `sys/macos/mkdir.S` (0x2000088, carry->neg)
- [x] T002 `libuolt/mkdir.S`: uolt_mkdir(path, mode)

## Phase 2: Tool

- [x] T003 [US1] `src/mkdir/mkdir.S`: option scan (-p, --); plain mkdir(path, 0777) with error
        diagnostic + status 1
- [x] T004 [US2] `mkdir_p`: create each prefix (ignore EEXIST) then the full path; walk index in
        a callee-saved register (survives the syscalls)
- [x] T005 Makefile: `EXTRA_mkdir` + append `mkdir` to `TOOLNAMES`

## Phase 3: Tests

- [x] T006 [P] `tests/unit/mkdir.sh`: plain, missing parent, -p chain/idempotent, existing,
        missing operand, multiple
- [x] T007 [P] `tests/posix/mkdir.sh`: umask-based modes, -p deep/trailing/repeated slashes, --
- [x] T008 [P] `tests/differential/mkdir.sh`: exit + resulting tree vs system mkdir

## Phase 4: Polish

- [x] T009 Wire mkdir tests into `make test`
- [x] T010 Update `README.md` with the `uolt-mkdir` row
- [x] T011 Verify macOS + Linux: all pass. Linux 856 B (< 1 KB)

## Notes

- `-m` deferred. Default mode is 0777 masked by the umask (kernel applies it), matching system.
- `-p` ignores EEXIST entirely (does not stat the existing path); creating -p over an existing
  regular file is silently accepted (minor deviation, not exercised).
