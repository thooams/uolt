// sys/linux/arm64/rename.S - Linux aarch64 rename, via renameat.
// sys_rename(old=x0, new=x1) -> renameat(AT_FDCWD, old, AT_FDCWD, new).
#include "uolt.inc"
.set SYS_RENAMEAT, 38
.set AT_FDCWD,     -100
.text
.globl sys_rename
sys_rename:
    mov     x3, x1                      // newpath
    mov     x1, x0                      // oldpath
    mov     x0, AT_FDCWD                // olddirfd
    mov     x2, AT_FDCWD                // newdirfd
    mov     x8, SYS_RENAMEAT
    svc     #0
    ret
