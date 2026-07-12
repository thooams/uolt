// sys/linux/getcwd.S - Linux x86_64 current-working-directory query.
//
// sys_getcwd(buf in rdi, size in rsi): fills buf with the NUL-terminated
// absolute path of the working directory. Linux has a direct getcwd syscall
// (79) that returns the length including the NUL (positive) on success, or a
// negative errno on failure. Callers only need the sign to detect errors.

#include "uolt.inc"

.set SYS_GETCWD, 79

.text
.globl sys_getcwd
sys_getcwd:
    mov     rax, SYS_GETCWD
    syscall                     // rax = length incl NUL (>0) or -errno
    ret
