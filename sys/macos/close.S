// sys/macos/close.S - macOS x86_64 `close` syscall wrapper.
//
// Owns the macOS syscall number (Principle V): BSD class 0x2000000 | 6. Arg
// follows the close(2) ABI: rdi=fd. The result is advisory for our use (we close
// files we opened after reading them), so the carry-flagged error is ignored.

#include "uolt.inc"

.set SYS_CLOSE, 0x2000006

.text
.globl sys_close
sys_close:
    mov     rax, SYS_CLOSE
    syscall
    ret
