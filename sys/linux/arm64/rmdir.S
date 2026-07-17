// sys/linux/arm64/rmdir.S - Linux aarch64 rmdir, via unlinkat|AT_REMOVEDIR.
// sys_rmdir(path=x0) -> unlinkat(AT_FDCWD, path, AT_REMOVEDIR).
#include "uolt.inc"
.set SYS_UNLINKAT,  35
.set AT_FDCWD,      -100
.set AT_REMOVEDIR,  0x200
.text
.globl sys_rmdir
sys_rmdir:
    mov     x1, x0                      // path
    mov     x0, AT_FDCWD
    mov     x2, AT_REMOVEDIR
    mov     x8, SYS_UNLINKAT
    svc     #0
    ret
