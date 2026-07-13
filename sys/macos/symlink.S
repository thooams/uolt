// sys/macos/symlink.S - macOS x86_64 `symlink` syscall wrapper (BSD 0x2000000|57).
// rdi = target, rsi = linkpath. Carry-flag error normalized to a negative return.
#include "uolt.inc"
.set SYS_SYMLINK, 0x2000039
.text
.globl sys_symlink
sys_symlink:
    mov     rax, SYS_SYMLINK
    syscall
    jc      1f
    ret
1:
    neg     rax
    ret
