// sys/linux/access.S - Linux access(2) primitive.
// sys_access(path in rdi, mode in rsi) -> rax = 0 on success or -errno. Owns the
// syscall number (Principle V). R_OK/W_OK/X_OK live in uolt.inc.
#include "uolt.inc"
.set SYS_ACCESS, 21
.text
.globl sys_access
sys_access:
    mov     rax, SYS_ACCESS
    syscall
    ret
