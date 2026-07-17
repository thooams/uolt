// libuolt/getcwd.S - internal API: uolt_getcwd(buf, size).
//
// Thin wrapper over the per-OS sys_getcwd (Principle V). rdi=buf, rsi=size;
// returns >= 0 on success (buf holds the NUL-terminated cwd) and < 0 on error,
// so callers can branch on the sign uniformly across Linux and macOS.

#include "uolt.inc"

.text
.globl uolt_getcwd
uolt_getcwd:
    jmp     sys_getcwd
