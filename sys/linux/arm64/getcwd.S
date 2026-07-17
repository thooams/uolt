// sys/linux/arm64/getcwd.S - Linux aarch64 wrapper. Owns the syscall number (Principle V).
// getcwd(2): x0=buf x1=size -> length incl NUL (>0)/-errno
#include "uolt.inc"
.set SYS_NR, 17
.text
.globl sys_getcwd
sys_getcwd:
    mov     x8, SYS_NR
    svc     #0
    ret
