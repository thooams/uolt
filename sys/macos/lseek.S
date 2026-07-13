// sys/macos/lseek.S - macOS x86_64 `lseek` syscall wrapper.
//
// Owns the macOS syscall number (Principle V): BSD class 0x2000000 | 199. Args
// follow the lseek(2) ABI: rdi=fd, rsi=offset, rdx=whence. BSD signals errors
// via the carry flag with errno in rax; we normalize to a negative return so
// callers see the same convention as Linux (offset >= 0, < 0 = error / ESPIPE).

#include "uolt.inc"

.set SYS_LSEEK, 0x20000C7

.text
.globl sys_lseek
sys_lseek:
    mov     rax, SYS_LSEEK
    syscall
    jc      1f
    ret
1:
    neg     rax                 // errno -> negative, uniform with Linux
    ret
