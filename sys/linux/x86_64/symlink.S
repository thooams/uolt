// sys/linux/symlink.S - Linux x86_64 `symlink` syscall wrapper.
// rdi = target (link contents), rsi = linkpath; returns 0 or -errno.
#include "uolt.inc"
.set SYS_SYMLINK, 88
.text
.globl sys_symlink
sys_symlink:
    mov     rax, SYS_SYMLINK
    syscall
    ret
