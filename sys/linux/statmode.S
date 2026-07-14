// sys/linux/statmode.S - Linux "stat, return st_mode" primitive.
// sys_statmode(path in rdi) -> rax = st_mode (>= 0) or -errno. Uses the stat
// syscall (4); st_mode is a u32 at offset 24 of struct stat. Owns the number and
// the struct offset (Principle V; both differ from macOS). Stat buffer on stack.
#include "uolt.inc"
.set SYS_STAT, 4
.text
.globl sys_statmode
sys_statmode:
    sub     rsp, 160
    mov     rsi, rsp
    mov     rax, SYS_STAT
    syscall
    test    rax, rax
    js      1f
    mov     eax, dword ptr [rsp + 24]   // st_mode (u32 at offset 24)
1:
    add     rsp, 160
    ret
