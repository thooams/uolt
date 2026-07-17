// sys/linux/mkdir.S - Linux x86_64 `mkdir` syscall wrapper.
//
// Owns the Linux syscall number (Principle V). Args: rdi = path, rsi = mode;
// returns 0 on success or a negative errno (e.g. -EEXIST) in rax.

#include "uolt.inc"

.set SYS_MKDIR, 83

.text
.globl sys_mkdir
sys_mkdir:
    mov     rax, SYS_MKDIR
    syscall
    ret
