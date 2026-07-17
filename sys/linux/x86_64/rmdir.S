// sys/linux/rmdir.S - Linux x86_64 `rmdir` syscall wrapper.
//
// Owns the Linux syscall number (Principle V). Arg: rdi = path; returns 0 on
// success or a negative errno (e.g. -ENOTEMPTY, -ENOENT) in rax.

#include "uolt.inc"

.set SYS_RMDIR, 84

.text
.globl sys_rmdir
sys_rmdir:
    mov     rax, SYS_RMDIR
    syscall
    ret
