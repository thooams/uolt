// sys/linux/arm64/getdents.S - Linux aarch64 wrapper. Owns the syscall number (Principle V).
// getdents64(2): x0=fd x1=buf x2=count -> bytes (0=end)/-errno
#include "uolt.inc"
.set SYS_NR, 61
.text
.globl sys_getdents
sys_getdents:
    mov     x8, SYS_NR
    svc     #0
    ret
