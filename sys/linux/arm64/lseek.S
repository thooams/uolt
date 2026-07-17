// sys/linux/arm64/lseek.S - Linux aarch64 wrapper. Owns the syscall number (Principle V).
// lseek(2): x0=fd x1=offset x2=whence -> offset/-errno
#include "uolt.inc"
.set SYS_NR, 62
.text
.globl sys_lseek
sys_lseek:
    mov     x8, SYS_NR
    svc     #0
    ret
