// sys/linux/arm64/statsize.S - Linux aarch64 "stat, return st_size", via newfstatat.
// sys_statsize(path=x0) -> x0 = st_size (>=0) or -errno. aarch64 st_size is an
// i64 at offset 48 (research D3).
#include "uolt.inc"
.set SYS_NEWFSTATAT, 79
.set AT_FDCWD,       -100
.set ST_SIZE_OFF,    48
.text
.globl sys_statsize
sys_statsize:
    sub     sp, sp, #160
    mov     x1, x0                      // path
    mov     x0, AT_FDCWD
    mov     x2, sp                      // &statbuf
    mov     x3, #0                      // flags (follow symlinks)
    mov     x8, SYS_NEWFSTATAT
    svc     #0
    cmp     x0, #0
    b.mi    1f
    ldr     x0, [sp, ST_SIZE_OFF]       // st_size (i64)
1:
    add     sp, sp, #160
    ret
