// sys/linux/link.S - Linux x86_64 `link` syscall wrapper.
// rdi = oldpath, rsi = newpath; returns 0 or -errno. Owns the number (Principle V).
#include "uolt.inc"
.set SYS_LINK, 86
.text
.globl sys_link
sys_link:
    mov     rax, SYS_LINK
    syscall
    ret
