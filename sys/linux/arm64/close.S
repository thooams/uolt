// sys/linux/arm64/close.S - Linux aarch64 wrapper. Owns the syscall number (Principle V).
// close(2): x0=fd -> 0/-errno
#include "uolt.inc"
.set SYS_NR, 57
.text
.globl sys_close
sys_close:
    mov     x8, SYS_NR
    svc     #0
    ret
