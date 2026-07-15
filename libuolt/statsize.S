// libuolt/statsize.S - internal API: uolt_statsize(path) -> st_size / -errno.
// Thin wrapper over per-OS sys_statsize (stat; follows symlinks).
#include "uolt.inc"
.text
.globl uolt_statsize
uolt_statsize:
    jmp     sys_statsize
