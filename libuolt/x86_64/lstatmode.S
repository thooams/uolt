// libuolt/lstatmode.S - internal API: uolt_lstatmode(path) -> st_mode / -errno.
// Thin wrapper over per-OS sys_lstatmode (lstat; does not follow symlinks).
#include "uolt.inc"
.text
.globl uolt_lstatmode
uolt_lstatmode:
    jmp     sys_lstatmode
