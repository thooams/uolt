// sys/linux/statsize.S - Linux "stat, return st_size" primitive (for `test -s`).
// sys_statsize(path in rdi) -> rax = st_size (>= 0) or -errno. Uses stat (4);
// st_size is an i64 at offset 48 of struct stat. Owns the number + offset.
#include "uolt.inc"
.set SYS_STAT, 4
.text
.globl sys_statsize
sys_statsize:
    sub     rsp, 160
    mov     rsi, rsp
    mov     rax, SYS_STAT
    syscall
    test    rax, rax
    js      1f
    mov     rax, qword ptr [rsp + 48]
1:
    add     rsp, 160
    ret
