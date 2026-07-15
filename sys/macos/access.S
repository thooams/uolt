// sys/macos/access.S - macOS access(2) primitive.
// sys_access(path in rdi, mode in rsi) -> rax = 0 on success or -errno. On error
// macOS sets the carry flag and returns errno in rax; negate so callers branch on
// sign uniformly. Owns the syscall number (Principle V).
#include "uolt.inc"
.set SYS_ACCESS, 0x2000021
.text
.globl sys_access
sys_access:
    mov     rax, SYS_ACCESS
    syscall
    jc      1f
    ret
1:
    neg     rax
    ret
