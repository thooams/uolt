// sys/linux/execve.S - Linux x86_64 `execve` syscall wrapper.
//
// Owns the Linux syscall number (Principle V). Args follow execve(2):
// rdi=path, rsi=argv, rdx=envp. On success it does not return (the image is
// replaced); on failure it returns a negative errno in rax.

#include "uolt.inc"

.set SYS_EXECVE, 59

.text
.globl sys_execve
sys_execve:
    mov     rax, SYS_EXECVE
    syscall                     // returns only on error: rax = -errno
    ret
