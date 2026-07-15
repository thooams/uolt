// libuolt/access.S - internal API: uolt_access(path, mode) -> 0 / -errno.
// Thin wrapper over per-OS sys_access (Principle V). Arguments already match.
#include "uolt.inc"
.text
.globl uolt_access
uolt_access:
    jmp     sys_access
