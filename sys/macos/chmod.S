// sys/macos/chmod.S - macOS x86_64 `chmod` syscall wrapper (BSD 0x2000000|15).
// rdi = path, rsi = mode. Carry-flag error normalized to a negative return.
#include "uolt.inc"
.set SYS_CHMOD, 0x200000F
.text
.globl sys_chmod
sys_chmod:
    mov     rax, SYS_CHMOD
    syscall
    jc      1f
    ret
1:
    neg     rax
    ret
