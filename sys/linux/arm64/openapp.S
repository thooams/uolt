// sys/linux/arm64/openapp.S - Linux aarch64 "open for append", via openat.
// sys_openapp(path=x0, mode=x1) -> openat(AT_FDCWD, path, O_WRONLY|O_CREAT|O_APPEND, mode).
#include "uolt.inc"
.set SYS_OPENAT, 56
.set AT_FDCWD,   -100
.set OFLAGS,     0x441              // O_WRONLY(1)|O_CREAT(0x40)|O_APPEND(0x400)
.text
.globl sys_openapp
sys_openapp:
    mov     x3, x1                      // mode
    mov     x1, x0                      // path
    mov     x0, AT_FDCWD
    mov     x2, OFLAGS
    mov     x8, SYS_OPENAT
    svc     #0
    ret
