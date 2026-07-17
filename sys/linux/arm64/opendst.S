// sys/linux/arm64/opendst.S - Linux aarch64 "open destination for copy", via openat.
// sys_opendst(path=x0, mode=x1) -> openat(AT_FDCWD, path, O_WRONLY|O_CREAT|O_TRUNC, mode).
#include "uolt.inc"
.set SYS_OPENAT, 56
.set AT_FDCWD,   -100
.set OFLAGS,     0x241              // O_WRONLY(1)|O_CREAT(0x40)|O_TRUNC(0x200)
.text
.globl sys_opendst
sys_opendst:
    mov     x3, x1                      // mode
    mov     x1, x0                      // path
    mov     x0, AT_FDCWD
    mov     x2, OFLAGS
    mov     x8, SYS_OPENAT
    svc     #0
    ret
