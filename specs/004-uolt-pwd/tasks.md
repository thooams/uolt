---
description: "Task list for uolt-pwd implementation"
---

# Tasks: uolt-pwd

**Prerequisites**: entry shim + libuolt write/strlen (from uolt-echo).

**Tests**: INCLUDED (Principle XI).

## Phase 1: Research

- [x] T001 Verify the cwd syscall path per OS: Linux getcwd(79) works; macOS __getcwd(326)
        raises SIGSYS (process killed) - use open(".")+fcntl(F_GETPATH)+close instead

## Phase 2: Foundational

- [x] T002 [P] `sys/linux/getcwd.S`: getcwd syscall wrapper (returns length / -errno)
- [x] T003 [P] `sys/macos/getcwd.S`: open(".")+fcntl(F_GETPATH)+close, returns 0 / -1
- [x] T004 `libuolt/getcwd.S`: uolt_getcwd(buf, size) over sys_getcwd

## Phase 3: Tool

- [x] T005 [US1] `src/pwd/pwd.S`: getcwd into a stack buffer, strlen, write path + newline,
        exit 0 (or 1 on error)
- [x] T006 Makefile: `EXTRA_pwd` + append `pwd` to `TOOLNAMES`

## Phase 4: Tests

- [x] T007 [P] `tests/unit/pwd.sh`: absolute path, trailing newline, matches `pwd -P` in a
        canonical temp dir (avoids macOS case-insensitive ambiguity)
- [x] T008 [P] `tests/differential/pwd.sh`: match `/bin/pwd -P` across /, /tmp, /usr, tempdir
- [x] T009 [P] `tests/trace/pwd.sh`: no mmap/brk; Linux shows getcwd

## Phase 5: Polish

- [x] T010 Wire pwd tests into `make test`
- [x] T011 Update `README.md` with the `uolt-pwd` row (size + system + speed)
- [x] T012 Verify macOS (`make test`) + Linux (`scripts/linux-test.sh`): all pass. Linux
        528 B, ~1.9× faster than /bin/pwd; trace/pwd proves no heap

## Notes

- v1 is physical (`-P`) only; `-L`/option parsing deferred.
- macOS reports the true on-disk case via F_GETPATH (can differ from a mixed-case cwd string).
