// sys/linux/arm64/statmode.S - Linux aarch64 "stat, return st_mode", via newfstatat.
// sys_statmode(path=x0) -> x0 = st_mode (>=0) or -errno. struct stat on the stack.
// aarch64 layout: st_mode is a u32 at offset 16 (research D3).
#include "uolt.inc"
.set SYS_NEWFSTATAT, 79
.set AT_FDCWD,       -100
.set ST_MODE_OFF,    16
.text
.globl sys_statmode
sys_statmode:
    sub     sp, sp, #160                // struct stat (128 bytes) on stack, 16-aligned
    mov     x1, x0                      // path
    mov     x0, AT_FDCWD
    mov     x2, sp                      // &statbuf
    mov     x3, #0                      // flags (follow symlinks)
    mov     x8, SYS_NEWFSTATAT
    svc     #0
    cmp     x0, #0
    b.mi    1f                          // negative -> return -errno as is
    ldr     w0, [sp, ST_MODE_OFF]       // st_mode (u32)
1:
    add     sp, sp, #160
    ret
