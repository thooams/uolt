// sys/linux/exit.S - Linux x86_64 `exit` syscall wrapper.
//
// Owns the Linux-specific syscall number so no tool or libuolt code names it
// (Principle V). Callers put the status in rdi and call sys_exit; this never
// returns.

#include "uolt.inc"

// Linux x86_64 syscall number for exit(2).
.set SYS_EXIT, 60

.text
.globl sys_exit
sys_exit:
    mov     rax, SYS_EXIT       // syscall number -> rax
    syscall                     // status already in rdi from the caller; does not return
