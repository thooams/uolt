// libuolt/mkdir.S - internal API: uolt_mkdir(path, mode).
//
// Thin wrapper over the per-OS sys_mkdir (Principle V). rdi = path, rsi = mode;
// returns 0 on success or a negative errno (notably -EEXIST) uniformly.

#include "uolt.inc"

.text
.globl uolt_mkdir
uolt_mkdir:
    jmp     sys_mkdir
