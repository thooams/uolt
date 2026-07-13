// sys/linux/unlink.S - Linux x86_64 `unlink` syscall wrapper.
// rdi = path; returns 0 or -errno. Owns the number (Principle V).
#include "uolt.inc"
.set SYS_UNLINK, 87
.text
.globl sys_unlink
sys_unlink:
    mov     rax, SYS_UNLINK
    syscall
    ret
