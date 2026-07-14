// sys/linux/umask.S - Linux `umask` syscall wrapper.
// sys_umask(mask in rdi) -> rax = previous mask. (Read the umask with umask(0)
// then restore it.) Owns the number (Principle V).
#include "uolt.inc"
.set SYS_UMASK, 95
.text
.globl sys_umask
sys_umask:
    mov     rax, SYS_UMASK
    syscall
    ret
