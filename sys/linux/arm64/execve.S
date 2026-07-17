// sys/linux/arm64/execve.S - Linux aarch64 wrapper. Owns the syscall number (Principle V).
// execve(2): x0=path x1=argv x2=envp; returns only on error (-errno)
#include "uolt.inc"
.set SYS_NR, 221
.text
.globl sys_execve
sys_execve:
    mov     x8, SYS_NR
    svc     #0
    ret
