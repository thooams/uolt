// sys/linux/munmap.S - Linux munmap primitive.
// sys_munmap(addr in rdi, len in rsi) -> rax = 0 or -errno. Owns the syscall
// number (Principle V). Used to release the old region after a growable buffer
// is moved to a larger mapping.
#include "uolt.inc"
.set SYS_MUNMAP, 11
.text
.globl sys_munmap
sys_munmap:
    mov     rax, SYS_MUNMAP
    syscall
    ret
