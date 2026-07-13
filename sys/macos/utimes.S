// sys/macos/utimes.S - macOS x86_64 `utimes` syscall wrapper.
//
// Owns the macOS syscall number (Principle V): BSD class 0x2000000 | 138. Args:
// rdi = path, rsi = times (struct timeval[2], or NULL for "now"). BSD signals
// errors via the carry flag; we normalize to a negative return (0 / -errno).

#include "uolt.inc"

.set SYS_UTIMES, 0x200008A

.text
.globl sys_utimes
sys_utimes:
    mov     rax, SYS_UTIMES
    syscall
    jc      1f
    ret
1:
    neg     rax
    ret
