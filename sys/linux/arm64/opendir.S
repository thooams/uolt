// sys/linux/arm64/opendir.S - Linux aarch64 "open a directory", via openat.
// sys_opendir(path=x0) -> openat(AT_FDCWD, path, O_RDONLY|O_DIRECTORY, 0). A
// non-directory fails -ENOTDIR. NOTE: O_DIRECTORY is 0x4000 on aarch64
// (asm-generic), not the 0x10000 x86_64 uses (research D2/D4).
#include "uolt.inc"
.set SYS_OPENAT,   56
.set AT_FDCWD,     -100
.set O_DIRECTORY,  0x4000
.text
.globl sys_opendir
sys_opendir:
    mov     x1, x0                      // path
    mov     x0, AT_FDCWD
    mov     x2, O_DIRECTORY             // O_RDONLY(0) | O_DIRECTORY
    mov     x3, #0                      // mode (unused)
    mov     x8, SYS_OPENAT
    svc     #0
    ret
