// libuolt/rmdir.S - internal API: uolt_rmdir(path).
//
// Thin wrapper over the per-OS sys_rmdir (Principle V). rdi = path; returns 0 on
// success or a negative errno uniformly.

#include "uolt.inc"

.text
.globl uolt_rmdir
uolt_rmdir:
    jmp     sys_rmdir
