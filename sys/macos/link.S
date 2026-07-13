// sys/macos/link.S - macOS x86_64 `link` syscall wrapper (BSD 0x2000000|9).
// rdi = oldpath, rsi = newpath. Carry-flag error normalized to a negative return.
#include "uolt.inc"
.set SYS_LINK, 0x2000009
.text
.globl sys_link
sys_link:
    mov     rax, SYS_LINK
    syscall
    jc      1f
    ret
1:
    neg     rax
    ret
