// sys/macos/write.S - macOS x86_64 `write` syscall wrapper.
//
// Owns the macOS syscall number (Principle V): BSD class 0x2000000 | 4. Args
// follow the write(2) ABI: rdi=fd, rsi=buf, rdx=count; returns byte count in rax
// (carry set on error, which we ignore for now).

#include "uolt.inc"

.set SYS_WRITE, 0x2000004

.text
.globl sys_write
sys_write:
    mov     rax, SYS_WRITE
    syscall
    ret
