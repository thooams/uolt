// sys/macos/exit.S - macOS x86_64 `exit` syscall wrapper.
//
// Owns the macOS-specific syscall number so no tool or libuolt code names it
// (Principle V). macOS uses the BSD syscall class 0x2000000 for Unix syscalls.
// Callers put the status in rdi and call sys_exit; this never returns.

#include "uolt.inc"

// macOS x86_64 syscall number for exit(2): BSD class (0x2000000) | 1.
.set SYS_EXIT, 0x2000001

.text
.globl sys_exit
sys_exit:
    mov     rax, SYS_EXIT       // syscall number -> rax
    syscall                     // status already in rdi from the caller; does not return
