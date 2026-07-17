// sys/linux/arm64/unlink.S - Linux aarch64 unlink, via unlinkat (flags 0).
// sys_unlink(path=x0) -> unlinkat(AT_FDCWD, path, 0).
#include "uolt.inc"
.set SYS_UNLINKAT, 35
.set AT_FDCWD,     -100
.text
.globl sys_unlink
sys_unlink:
    mov     x1, x0                      // path
    mov     x0, AT_FDCWD
    mov     x2, #0                      // flags
    mov     x8, SYS_UNLINKAT
    svc     #0
    ret
