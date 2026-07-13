// libuolt/create.S - internal API: uolt_create(path, mode) -> fd.
//
// Thin wrapper over the per-OS sys_create (Principle V), which opens the path
// O_WRONLY|O_CREAT (the O_CREAT flag value differs by OS). rdi = path, rsi = mode;
// returns a descriptor (>= 0) or a negative errno.

#include "uolt.inc"

.text
.globl uolt_create
uolt_create:
    jmp     sys_create
