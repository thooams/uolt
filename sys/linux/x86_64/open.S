// sys/linux/open.S - Linux x86_64 `open` syscall wrapper.
//
// Owns the Linux syscall number (Principle V). Args follow the open(2) ABI:
// rdi=path, rsi=flags, rdx=mode; returns a file descriptor (>= 0) or a negative
// errno in rax. Callers branch on the sign to detect failure.

#include "uolt.inc"

.set SYS_OPEN, 2

.text
.globl sys_open
sys_open:
    mov     rax, SYS_OPEN
    syscall                     // rax = fd (>=0) or -errno
    ret
