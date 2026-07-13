// sys/macos/rename.S - macOS x86_64 `rename` syscall wrapper (BSD 0x2000000|128).
// rdi = oldpath, rsi = newpath. Carry-flag error normalized to a negative return.
#include "uolt.inc"
.set SYS_RENAME, 0x2000080
.text
.globl sys_rename
sys_rename:
    mov     rax, SYS_RENAME
    syscall
    jc      1f
    ret
1:
    neg     rax
    ret
