// sys/macos/statsize.S - macOS "stat, return st_size" primitive (for `test -s`).
// sys_statsize(path in rdi) -> rax = st_size (>= 0) or -errno. Uses stat64
// (0x2000000|338); st_size is an i64 at offset 96 of the 64-bit struct stat
// (after the four 16-byte timespecs).
#include "uolt.inc"
.set SYS_STAT64, 0x2000152
.text
.globl sys_statsize
sys_statsize:
    sub     rsp, 160
    mov     rsi, rsp
    mov     rax, SYS_STAT64
    syscall
    jc      1f
    mov     rax, qword ptr [rsp + 96]
    add     rsp, 160
    ret
1:
    neg     rax
    add     rsp, 160
    ret
