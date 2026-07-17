// sys/linux/lseek.S - Linux x86_64 `lseek` syscall wrapper.
//
// Owns the Linux syscall number (Principle V). Args follow the lseek(2) ABI:
// rdi=fd, rsi=offset, rdx=whence; returns the resulting absolute offset (>= 0)
// or a negative errno in rax (e.g. -ESPIPE for a pipe). Callers branch on sign.

#include "uolt.inc"

.set SYS_LSEEK, 8

.text
.globl sys_lseek
sys_lseek:
    mov     rax, SYS_LSEEK
    syscall                     // rax = new offset (>=0) or -errno
    ret
