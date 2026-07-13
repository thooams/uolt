// sys/macos/opendir.S - macOS "open a directory" primitive.
// sys_opendir(path in rdi) -> fd: open O_RDONLY|O_DIRECTORY. O_DIRECTORY is
// 0x100000 on macOS (0x10000 on Linux). A non-directory fails with -ENOTDIR.
// Carry-flag error normalized to a negative return.
#include "uolt.inc"
.set SYS_OPEN,     0x2000005
.set O_DIRECTORY,  0x100000
.text
.globl sys_opendir
sys_opendir:
    mov     rsi, O_DIRECTORY
    xor     rdx, rdx
    mov     rax, SYS_OPEN
    syscall
    jc      1f
    ret
1:
    neg     rax
    ret
