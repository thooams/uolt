// sys/macos/statmode.S - macOS "stat, return st_mode" primitive.
// sys_statmode(path in rdi) -> rax = st_mode (>= 0) or -errno. Uses stat64
// (0x2000000|338); st_mode is a u16 at offset 4 of the 64-bit struct stat. macOS
// stat64 works as a direct syscall (verified, unlike getcwd/nanosleep).
#include "uolt.inc"
.set SYS_STAT64, 0x2000152
.text
.globl sys_statmode
sys_statmode:
    sub     rsp, 160
    mov     rsi, rsp
    mov     rax, SYS_STAT64
    syscall
    jc      1f
    movzx   eax, word ptr [rsp + 4]     // st_mode (u16 at offset 4)
    add     rsp, 160
    ret
1:
    neg     rax
    add     rsp, 160
    ret
