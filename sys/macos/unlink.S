// sys/macos/unlink.S - macOS x86_64 `unlink` syscall wrapper (BSD 0x2000000|10).
// rdi = path. Carry-flag error normalized to a negative return.
#include "uolt.inc"
.set SYS_UNLINK, 0x200000A
.text
.globl sys_unlink
sys_unlink:
    mov     rax, SYS_UNLINK
    syscall
    jc      1f
    ret
1:
    neg     rax
    ret
