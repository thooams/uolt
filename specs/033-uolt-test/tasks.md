---
description: "Task list for uolt-test implementation"
---
# Tasks: uolt-test
- [x] T001 sys/<os>/{access,lstatmode,statsize}.S + libuolt wrappers; S_IF*/R_OK bits in uolt.inc
- [x] T002 src/test/test.S: bracket detection + trailing `]` strip; operand-count dispatch
- [x] T003 POSIX 1/2/3/4-argument helpers (one/two/three/four_args)
- [x] T004 Recursive-descent grammar (or_expr/and_expr/factor/primary) for >= 5 operands
- [x] T005 Primaries: apply_unop (string/stat/lstat/access) + apply_binop (string / integer)
- [x] T006 Recognizers is_unop/is_binop; helpers test_streq/test_atoi/basename_ptr
- [x] T007 Makefile: EXTRA_test + TOOLNAMES; install/uninstall also manage the `[` symlink
- [x] T008 tests/unit/test.sh + tests/differential/test.sh (the `[` alias via a symlink)
- [x] T009 README row; verify macOS + Linux (2592 B)

## Notes
- Same stack-locals-below-40 rule as printf (five pushed callee-saved registers sit in
  [rbp-8..-40]). r15/r14 hold the operand base/count for the whole evaluation; helpers read them
  but never write them, keeping per-call state in rbx (saved/restored) or stack locals.
- Syntax errors unwind by `lea rsp, [rbp-40]` + the register pops, so the grammar can bail out from
  any recursion depth without threading an error flag back up.
- st_size offset differs by OS (Linux 48 / macOS 96, after the four 16-byte timespecs); lstat64 is
  BSD syscall 340 (0x2000154). `-t` deferred (needs a terminal ioctl).
