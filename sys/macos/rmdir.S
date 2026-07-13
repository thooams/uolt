// sys/macos/rmdir.S - macOS x86_64 `rmdir` syscall wrapper.
//
// Owns the macOS syscall number (Principle V): BSD class 0x2000000 | 137. Arg:
// rdi = path. BSD signals errors via the carry flag with errno in rax; we
// normalize to a negative return so callers match Linux (0 / -errno).

#include "uolt.inc"

.set SYS_RMDIR, 0x2000089

.text
.globl sys_rmdir
sys_rmdir:
    mov     rax, SYS_RMDIR
    syscall
    jc      1f
    ret
1:
    neg     rax
    ret
