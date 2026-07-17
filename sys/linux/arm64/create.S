// sys/linux/arm64/create.S - Linux aarch64 "open for create", via openat.
// sys_create(path=x0, mode=x1) -> openat(AT_FDCWD, path, O_WRONLY|O_CREAT, mode).
#include "uolt.inc"
.set SYS_OPENAT, 56
.set AT_FDCWD,   -100
.set OFLAGS,     0x41               // O_WRONLY(1)|O_CREAT(0x40)
.text
.globl sys_create
sys_create:
    mov     x3, x1                      // mode
    mov     x1, x0                      // path
    mov     x0, AT_FDCWD
    mov     x2, OFLAGS
    mov     x8, SYS_OPENAT
    svc     #0
    ret
