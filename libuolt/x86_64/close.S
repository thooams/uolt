// libuolt/close.S - internal API: uolt_close(fd).
//
// Thin wrapper over the per-OS sys_close (Principle V). The fd is already in rdi,
// so this is a tail call; the result stays in rax.

#include "uolt.inc"

.text
.globl uolt_close
uolt_close:
    jmp     sys_close
