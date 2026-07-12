// sys/linux/write.S - Linux x86_64 `write` syscall wrapper.
//
// Owns the Linux syscall number (Principle V). Args follow the write(2) ABI:
// rdi=fd, rsi=buf, rdx=count; returns the byte count (or negative errno) in rax.

#include "uolt.inc"

.set SYS_WRITE, 1

.text
.globl sys_write
sys_write:
    mov     rax, SYS_WRITE
    syscall
    ret
