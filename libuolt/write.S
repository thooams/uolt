// libuolt/write.S - internal API: uolt_write(fd, buf, len).
//
// Thin wrapper so tools use the libuolt API instead of naming a syscall
// (Principle V). Arguments already match the write ABI (rdi=fd, rsi=buf,
// rdx=len), so this is a tail call to the per-OS sys_write; result stays in rax.

#include "uolt.inc"

.text
.globl uolt_write
uolt_write:
    jmp     sys_write
