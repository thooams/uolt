// sys/linux/arm64/mkdir.S - Linux aarch64 mkdir, via mkdirat.
// sys_mkdir(path=x0, mode=x1) -> mkdirat(AT_FDCWD, path, mode).
#include "uolt.inc"
.set SYS_MKDIRAT, 34
.set AT_FDCWD,    -100
.text
.globl sys_mkdir
sys_mkdir:
    mov     x2, x1                      // mode
    mov     x1, x0                      // path
    mov     x0, AT_FDCWD
    mov     x8, SYS_MKDIRAT
    svc     #0
    ret
