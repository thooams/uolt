// sys/linux/arm64/lstatmode.S - Linux aarch64 "lstat, return st_mode", via newfstatat.
// sys_lstatmode(path=x0) -> x0 = st_mode (>=0) or -errno; does NOT follow symlinks
// (AT_SYMLINK_NOFOLLOW). aarch64 st_mode is a u32 at offset 16 (research D3).
#include "uolt.inc"
.set SYS_NEWFSTATAT,        79
.set AT_FDCWD,              -100
.set AT_SYMLINK_NOFOLLOW,   0x100
.set ST_MODE_OFF,           16
.text
.globl sys_lstatmode
sys_lstatmode:
    sub     sp, sp, #160
    mov     x1, x0                      // path
    mov     x0, AT_FDCWD
    mov     x2, sp                      // &statbuf
    mov     x3, AT_SYMLINK_NOFOLLOW
    mov     x8, SYS_NEWFSTATAT
    svc     #0
    cmp     x0, #0
    b.mi    1f
    ldr     w0, [sp, ST_MODE_OFF]
1:
    add     sp, sp, #160
    ret
