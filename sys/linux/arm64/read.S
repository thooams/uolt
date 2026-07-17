// sys/linux/arm64/read.S - Linux aarch64 wrapper. Owns the syscall number (Principle V).
// read(2): x0=fd x1=buf x2=count -> bytes (0=EOF)/-errno
#include "uolt.inc"
.set SYS_NR, 63
.text
.globl sys_read
sys_read:
    mov     x8, SYS_NR
    svc     #0
    ret
