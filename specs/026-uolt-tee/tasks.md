---
description: "Task list for uolt-tee implementation"
---
# Tasks: uolt-tee
- [x] T001 sys/{linux,macos}/openapp.S + libuolt/openapp.S (O_WRONLY|O_CREAT|O_APPEND)
- [x] T002 src/tee/tee.S: -a/--, open files into a stack fd array, read/drain to stdout+files, close
- [x] T003 Makefile: EXTRA_tee + TOOLNAMES
- [x] T004 tests/unit/tee.sh (fan-out, -a, truncate, passthrough, binary, bad file)
- [x] T005 tests/differential/tee.sh (vs system tee)
- [x] T006 README row; verify macOS + Linux (960 B)

## Notes
- Bug: the epilogue `add rsp` did not match the prologue `sub rsp` after the stack size was
  bumped (off by 16), corrupting the return address (crash in dyld). Keep sub/add in lockstep.
