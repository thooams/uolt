// sys/linux/read.S - Linux x86_64 `read` syscall wrapper.
//
// Owns the Linux syscall number (Principle V). Args follow the read(2) ABI:
// rdi=fd, rsi=buf, rdx=count; returns the byte count read (0 at EOF) or a
// negative errno in rax.

#include "uolt.inc"

.set SYS_READ, 0

.text
.globl sys_read
sys_read:
    mov     rax, SYS_READ
    syscall                     // rax = bytes read (0=EOF) or -errno
    ret
