// sys/linux/chmod.S - Linux x86_64 `chmod` syscall wrapper.
// rdi = path, rsi = mode; returns 0 or -errno. Owns the number (Principle V).
#include "uolt.inc"
.set SYS_CHMOD, 90
.text
.globl sys_chmod
sys_chmod:
    mov     rax, SYS_CHMOD
    syscall
    ret
