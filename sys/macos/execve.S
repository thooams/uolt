// sys/macos/execve.S - macOS x86_64 `execve` syscall wrapper.
//
// Owns the macOS syscall number (Principle V): BSD class 0x2000000 | 59. Args
// follow execve(2): rdi=path, rsi=argv, rdx=envp. On success it does not return;
// on failure the carry flag is set with errno in rax, which we normalize to a
// negative return to match the Linux convention.

#include "uolt.inc"

.set SYS_EXECVE, 0x200003B

.text
.globl sys_execve
sys_execve:
    mov     rax, SYS_EXECVE
    syscall
    jc      1f
    ret
1:
    neg     rax                 // errno -> negative, uniform with Linux
    ret
