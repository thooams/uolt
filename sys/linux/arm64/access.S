// sys/linux/arm64/access.S - Linux aarch64 access, via faccessat.
// sys_access(path=x0, mode=x1) -> faccessat(AT_FDCWD, path, mode, 0).
#include "uolt.inc"
.set SYS_FACCESSAT, 48
.set AT_FDCWD,      -100
.text
.globl sys_access
sys_access:
    mov     x2, x1                      // mode
    mov     x1, x0                      // path
    mov     x0, AT_FDCWD
    mov     x3, #0                      // flags
    mov     x8, SYS_FACCESSAT
    svc     #0
    ret
