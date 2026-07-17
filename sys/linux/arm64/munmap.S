// sys/linux/arm64/munmap.S - Linux aarch64 wrapper. Owns the syscall number (Principle V).
// munmap(2): x0=addr x1=len -> 0/-errno
#include "uolt.inc"
.set SYS_NR, 215
.text
.globl sys_munmap
sys_munmap:
    mov     x8, SYS_NR
    svc     #0
    ret
