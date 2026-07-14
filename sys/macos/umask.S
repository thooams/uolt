// sys/macos/umask.S - macOS `umask` syscall wrapper (BSD 0x2000000|60).
// sys_umask(mask in rdi) -> rax = previous mask.
#include "uolt.inc"
.set SYS_UMASK, 0x200003C
.text
.globl sys_umask
sys_umask:
    mov     rax, SYS_UMASK
    syscall
    ret
