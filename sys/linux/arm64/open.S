// sys/linux/arm64/open.S - Linux aarch64 open, via openat (aarch64 has no open).
// sys_open(path=x0, flags=x1, mode=x2) -> openat(AT_FDCWD, path, flags, mode).
// Absorbs the *at shape so callers keep the plain open signature (research D2).
#include "uolt.inc"
.set SYS_OPENAT, 56
.set AT_FDCWD,   -100
.text
.globl sys_open
sys_open:
    mov     x3, x2                      // mode  -> openat arg3
    mov     x2, x1                      // flags -> openat arg2
    mov     x1, x0                      // path  -> openat arg1
    mov     x0, AT_FDCWD                // dirfd -> openat arg0
    mov     x8, SYS_OPENAT
    svc     #0
    ret
