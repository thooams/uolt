// sys/macos/munmap.S - macOS munmap primitive.
// sys_munmap(addr in rdi, len in rsi) -> rax = 0 or -errno. On error macOS sets
// the carry flag and returns errno; negate so callers branch on sign.
#include "uolt.inc"
.set SYS_MUNMAP, 0x2000049
.text
.globl sys_munmap
sys_munmap:
    mov     rax, SYS_MUNMAP
    syscall
    jc      1f
    ret
1:
    neg     rax
    ret
