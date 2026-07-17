// sys/linux/opendst.S - Linux "open destination for copy" primitive.
// sys_opendst(path in rdi, mode in rsi) -> fd: open O_WRONLY|O_CREAT|O_TRUNC.
// Owns the number and the OS-specific flags (Principle V): O_TRUNC differs by OS.
#include "uolt.inc"
.set SYS_OPEN, 2
.set OFLAGS,    0x241            // O_WRONLY(1)|O_CREAT(0x40)|O_TRUNC(0x200)
.text
.globl sys_opendst
sys_opendst:
    mov     rdx, rsi
    mov     rsi, OFLAGS
    mov     rax, SYS_OPEN
    syscall
    ret
