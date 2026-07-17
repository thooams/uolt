// sys/linux/arm64/symlink.S - Linux aarch64 symlink, via symlinkat.
// sys_symlink(target=x0, linkpath=x1) -> symlinkat(target, AT_FDCWD, linkpath).
#include "uolt.inc"
.set SYS_SYMLINKAT, 36
.set AT_FDCWD,      -100
.text
.globl sys_symlink
sys_symlink:
    mov     x2, x1                      // linkpath -> arg2
    mov     x1, AT_FDCWD                // newdirfd -> arg1
    mov     x8, SYS_SYMLINKAT           // target stays in x0
    svc     #0
    ret
