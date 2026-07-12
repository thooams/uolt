// sys/macos/open.S - macOS x86_64 `open` syscall wrapper.
//
// Owns the macOS syscall number (Principle V): BSD class 0x2000000 | 5. Args
// follow the open(2) ABI: rdi=path, rsi=flags, rdx=mode. On BSD, errors are
// signalled by the carry flag with errno in rax; we normalize that to a negative
// return so callers see the same sign convention as Linux (fd >= 0 / < 0 error).

#include "uolt.inc"

.set SYS_OPEN, 0x2000005

.text
.globl sys_open
sys_open:
    mov     rax, SYS_OPEN
    syscall
    jc      1f                  // carry set -> error, errno in rax
    ret
1:
    neg     rax                 // errno -> negative, uniform with Linux
    ret
