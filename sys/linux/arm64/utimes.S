// sys/linux/arm64/utimes.S - Linux aarch64 utimes, via utimensat.
// sys_utimes(path=x0, times=x1): times is a struct timeval[2] (or NULL for "now").
// aarch64 has no utimes; utimensat takes struct timespec[2], so convert each
// tv_usec to tv_nsec (*1000) into a stack buffer (research D2). NULL -> now.
#include "uolt.inc"
.set SYS_UTIMENSAT, 88
.set AT_FDCWD,      -100
.text
.globl sys_utimes
sys_utimes:
    sub     sp, sp, #32                 // struct timespec[2]
    cbz     x1, .Lnow                   // NULL times -> current time
    mov     x3, #1000                   // usec -> nsec factor
    ldr     x2, [x1]                    // times[0].tv_sec
    str     x2, [sp]
    ldr     x2, [x1, #8]                // times[0].tv_usec
    mul     x2, x2, x3
    str     x2, [sp, #8]                // ts[0].tv_nsec
    ldr     x2, [x1, #16]               // times[1].tv_sec
    str     x2, [sp, #16]
    ldr     x2, [x1, #24]               // times[1].tv_usec
    mul     x2, x2, x3
    str     x2, [sp, #24]               // ts[1].tv_nsec
    mov     x2, sp                      // times = &ts
    b       .Lgo
.Lnow:
    mov     x2, #0                      // NULL -> set to now
.Lgo:
    mov     x1, x0                      // path
    mov     x0, AT_FDCWD
    mov     x3, #0                      // flags
    mov     x8, SYS_UTIMENSAT
    svc     #0
    add     sp, sp, #32
    ret
