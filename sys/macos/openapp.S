// sys/macos/openapp.S - macOS "open for append" primitive.
// sys_openapp(path in rdi, mode in rsi) -> fd: open O_WRONLY|O_CREAT|O_APPEND.
// O_APPEND is 0x8 on macOS, O_CREAT 0x200. Carry-flag error -> negative return.
#include "uolt.inc"
.set SYS_OPEN, 0x2000005
.set OFLAGS,   0x209            // O_WRONLY(1)|O_CREAT(0x200)|O_APPEND(0x8)
.text
.globl sys_openapp
sys_openapp:
    mov     rdx, rsi
    mov     rsi, OFLAGS
    mov     rax, SYS_OPEN
    syscall
    jc      1f
    ret
1:
    neg     rax
    ret
