// sys/linux/rename.S - Linux x86_64 `rename` syscall wrapper.
// rdi = oldpath, rsi = newpath; returns 0 or -errno. Owns the number (Principle V).
#include "uolt.inc"
.set SYS_RENAME, 82
.text
.globl sys_rename
sys_rename:
    mov     rax, SYS_RENAME
    syscall
    ret
