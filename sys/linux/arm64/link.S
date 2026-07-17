// sys/linux/arm64/link.S - Linux aarch64 link, via linkat.
// sys_link(old=x0, new=x1) -> linkat(AT_FDCWD, old, AT_FDCWD, new, 0).
#include "uolt.inc"
.set SYS_LINKAT, 37
.set AT_FDCWD,   -100
.text
.globl sys_link
sys_link:
    mov     x3, x1                      // newpath
    mov     x1, x0                      // oldpath
    mov     x0, AT_FDCWD                // olddirfd
    mov     x2, AT_FDCWD                // newdirfd
    mov     x4, #0                      // flags
    mov     x8, SYS_LINKAT
    svc     #0
    ret
