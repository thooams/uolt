// sys/macos/opendst.S - macOS "open destination for copy" primitive.
// sys_opendst(path in rdi, mode in rsi) -> fd: open O_WRONLY|O_CREAT|O_TRUNC.
// O_TRUNC is 0x400 on macOS (0x200 on Linux). Carry-flag error -> negative.
#include "uolt.inc"
.set SYS_OPEN, 0x2000005
.set OFLAGS,    0x601            // O_WRONLY(1)|O_CREAT(0x200)|O_TRUNC(0x400)
.text
.globl sys_opendst
sys_opendst:
    mov     rdx, rsi
    mov     rsi, OFLAGS
    mov     rax, SYS_OPEN
    syscall
    jc      1f
    ret
1:
    neg     rax
    ret
