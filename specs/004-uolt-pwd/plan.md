# Implementation Plan: uolt-pwd

**Branch**: `main` (spec dir `004-uolt-pwd`) | **Date**: 2026-07-12 | **Spec**: [spec.md](./spec.md)

## Summary

First tool that reads system state. Prints the physical working directory. The interesting
part is entirely in the per-OS cwd wrapper.

## Technical Context

Same toolchain and conventions as prior tools. New:
- **cwd query differs sharply by OS (verified empirically)**:
  - **Linux**: direct `getcwd` syscall (79), returns length incl NUL or negative errno.
  - **macOS**: the direct `__getcwd` syscall (326) raises **SIGSYS** and the kernel kills the
    process. macOS gates it. Worked around with allowed syscalls: `open(".", O_RDONLY)` +
    `fcntl(fd, F_GETPATH, buf)` + `close(fd)`.
  Both are hidden behind one `sys_getcwd(buf, size)` returning `>= 0` on success / `< 0` on
  error, so the tool branches on the sign uniformly.
- **No heap**: the path is read into a stack buffer (BUFSZ 4096).

## Constitution Check

| Principle | Status | Note |
|-----------|--------|------|
| I–V, VIII–XI | PASS | pure asm, direct syscalls, no heap, per-OS abstraction, POSIX, tested |
| VI (size) | PASS Linux (528 B < 2 KB); macOS ~5.5 KB Mach-O floor |
| VII / perf | PASS | ~1.9× faster than system `pwd` on Linux (hyperfine) |

The macOS SIGSYS discovery is a concrete instance of the constitution's noted tension that
some direct syscalls are restricted on Apple platforms; here it is resolved for x86_64 pwd.

## Project Structure

New:

```text
sys/linux/getcwd.S    # getcwd syscall (79)
sys/macos/getcwd.S    # open(".") + fcntl(F_GETPATH) + close
libuolt/getcwd.S      # uolt_getcwd(buf, size)
src/pwd/pwd.S         # the tool: getcwd into a stack buffer, write + newline
tests/{unit,differential,trace}/pwd.sh
```

Makefile: `EXTRA_pwd` adds getcwd/strlen/write (libuolt) + getcwd/write (sys). `pwd` appended
to `TOOLNAMES`.

## Complexity Tracking

> No violations.
