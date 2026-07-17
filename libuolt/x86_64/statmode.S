// libuolt/statmode.S - internal API: uolt_statmode(path) -> st_mode.
// Thin wrapper over per-OS sys_statmode (stat + return st_mode; syscall number
// and struct offset differ by OS). Returns st_mode (>= 0) or a negative errno.
#include "uolt.inc"
.text
.globl uolt_statmode
uolt_statmode:
    jmp     sys_statmode
