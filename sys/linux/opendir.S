// sys/linux/opendir.S - Linux "open a directory" primitive.
// sys_opendir(path in rdi) -> fd: open O_RDONLY|O_DIRECTORY, so a non-directory
// fails with -ENOTDIR (letting the caller detect files without stat). Owns the
// number and the OS-specific O_DIRECTORY flag (Principle V).
#include "uolt.inc"
.set SYS_OPEN,     2
.set O_DIRECTORY,  0x10000
.text
.globl sys_opendir
sys_opendir:
    mov     rsi, O_DIRECTORY
    xor     rdx, rdx
    mov     rax, SYS_OPEN
    syscall
    ret
