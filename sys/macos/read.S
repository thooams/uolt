// sys/macos/read.S - macOS x86_64 `read` syscall wrapper.
//
// Owns the macOS syscall number (Principle V): BSD class 0x2000000 | 3. Args
// follow the read(2) ABI: rdi=fd, rsi=buf, rdx=count. BSD signals errors via the
// carry flag with errno in rax; we normalize to a negative return so callers see
// the same convention as Linux (bytes >= 0, 0 = EOF, < 0 = error).

#include "uolt.inc"

.set SYS_READ, 0x2000003

.text
.globl sys_read
sys_read:
    mov     rax, SYS_READ
    syscall
    jc      1f
    ret
1:
    neg     rax                 // errno -> negative, uniform with Linux
    ret
