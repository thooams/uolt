// sys/linux/arm64/umask.S - Linux aarch64 wrapper. Owns the syscall number (Principle V).
// umask(2): x0=mask -> previous mask
#include "uolt.inc"
.set SYS_NR, 166
.text
.globl sys_umask
sys_umask:
    mov     x8, SYS_NR
    svc     #0
    ret
