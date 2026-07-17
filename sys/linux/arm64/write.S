// sys/linux/arm64/write.S - Linux aarch64 `write` syscall wrapper.
//
// Owns the Linux aarch64 syscall number (Principle V). Args follow the write(2)
// ABI, already in the AArch64 argument registers: x0=fd, x1=buf, x2=count;
// returns the byte count (or negative errno) in x0. Syscall number in x8.

#include "uolt.inc"

.set SYS_WRITE, 64

.text
.globl sys_write
sys_write:
    mov     x8, SYS_WRITE
    svc     #0
    ret
