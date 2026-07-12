// sys/linux/close.S - Linux x86_64 `close` syscall wrapper.
//
// Owns the Linux syscall number (Principle V). Arg follows the close(2) ABI:
// rdi=fd; returns 0 on success or a negative errno in rax.

#include "uolt.inc"

.set SYS_CLOSE, 3

.text
.globl sys_close
sys_close:
    mov     rax, SYS_CLOSE
    syscall
    ret
