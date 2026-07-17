// sys/linux/utimes.S - Linux x86_64 `utimes` syscall wrapper.
//
// Owns the Linux syscall number (Principle V). Args: rdi = path, rsi = times
// (struct timeval[2], or NULL for "now"); returns 0 or a negative errno.

#include "uolt.inc"

.set SYS_UTIMES, 235

.text
.globl sys_utimes
sys_utimes:
    mov     rax, SYS_UTIMES
    syscall
    ret
