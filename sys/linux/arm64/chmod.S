// sys/linux/arm64/chmod.S - Linux aarch64 chmod, via fchmodat.
// sys_chmod(path=x0, mode=x1) -> fchmodat(AT_FDCWD, path, mode, 0).
#include "uolt.inc"
.set SYS_FCHMODAT, 53
.set AT_FDCWD,     -100
.text
.globl sys_chmod
sys_chmod:
    mov     x2, x1                      // mode
    mov     x1, x0                      // path
    mov     x0, AT_FDCWD
    mov     x3, #0                      // flags
    mov     x8, SYS_FCHMODAT
    svc     #0
    ret
