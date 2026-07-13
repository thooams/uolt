// sys/macos/mkdir.S - macOS x86_64 `mkdir` syscall wrapper.
//
// Owns the macOS syscall number (Principle V): BSD class 0x2000000 | 136. Args:
// rdi = path, rsi = mode. BSD signals errors via the carry flag with errno in
// rax; we normalize to a negative return so callers match Linux (0 / -errno,
// e.g. -EEXIST).

#include "uolt.inc"

.set SYS_MKDIR, 0x2000088

.text
.globl sys_mkdir
sys_mkdir:
    mov     rax, SYS_MKDIR
    syscall
    jc      1f
    ret
1:
    neg     rax
    ret
