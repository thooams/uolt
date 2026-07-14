---
description: "Task list for uolt-env implementation"
---
# Tasks: uolt-env
- [x] T001 src/env/env.S: envp = argv+(argc+1)*8; loop print each entry + newline
- [x] T002 Makefile: EXTRA_env + TOOLNAMES
- [x] T003 tests/unit/env.sh (var present, NAME=value lines, trailing newline)
- [x] T004 tests/differential/env.sh (vs system env, sorted, excluding "_")
- [x] T005 README row; verify macOS + Linux (496 B)

## Notes
- envp follows argv's NULL terminator in memory on both Linux (stack) and macOS (LC_MAIN), so no
  shim change was needed. The shell-set "_" (path of the running program) legitimately differs
  between binaries and is excluded from the differential comparison.
