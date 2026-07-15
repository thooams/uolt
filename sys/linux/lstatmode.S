// sys/linux/lstatmode.S - Linux "lstat, return st_mode" primitive (does not
// follow symlinks, so `test -h`/`-L` can detect the link itself).
// sys_lstatmode(path in rdi) -> rax = st_mode (>= 0) or -errno. Uses lstat (6);
// st_mode is a u32 at offset 24 of struct stat. Owns the number + offset.
#include "uolt.inc"
.set SYS_LSTAT, 6
.text
.globl sys_lstatmode
sys_lstatmode:
    sub     rsp, 160
    mov     rsi, rsp
    mov     rax, SYS_LSTAT
    syscall
    test    rax, rax
    js      1f
    mov     eax, dword ptr [rsp + 24]
1:
    add     rsp, 160
    ret
