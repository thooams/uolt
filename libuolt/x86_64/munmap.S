// libuolt/munmap.S - internal API: uolt_munmap(addr, len) -> 0 / -errno.
// Thin wrapper over the per-OS sys_munmap (Principle V).
#include "uolt.inc"
.text
.globl uolt_munmap
uolt_munmap:
    jmp     sys_munmap
