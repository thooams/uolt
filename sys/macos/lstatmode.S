// sys/macos/lstatmode.S - macOS "lstat, return st_mode" primitive.
// sys_lstatmode(path in rdi) -> rax = st_mode (>= 0) or -errno. Uses lstat64
// (0x2000000|340); st_mode is a u16 at offset 4 of the 64-bit struct stat. Works
// as a direct syscall (verified, like stat64).
#include "uolt.inc"
.set SYS_LSTAT64, 0x2000154
.text
.globl sys_lstatmode
sys_lstatmode:
    sub     rsp, 160
    mov     rsi, rsp
    mov     rax, SYS_LSTAT64
    syscall
    jc      1f
    movzx   eax, word ptr [rsp + 4]
    add     rsp, 160
    ret
1:
    neg     rax
    add     rsp, 160
    ret
