// sys/linux/openapp.S - Linux "open for append" primitive.
// sys_openapp(path in rdi, mode in rsi) -> fd: open O_WRONLY|O_CREAT|O_APPEND.
// Owns the number + OS-specific flags (Principle V): O_APPEND differs by OS.
#include "uolt.inc"
.set SYS_OPEN, 2
.set OFLAGS,   0x441            // O_WRONLY(1)|O_CREAT(0x40)|O_APPEND(0x400)
.text
.globl sys_openapp
sys_openapp:
    mov     rdx, rsi
    mov     rsi, OFLAGS
    mov     rax, SYS_OPEN
    syscall
    ret
