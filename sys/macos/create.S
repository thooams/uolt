// sys/macos/create.S - macOS x86_64 "open for create" primitive.
//
// sys_create(path in rdi, mode in rsi) -> fd: open the path O_WRONLY|O_CREAT.
// Owns the macOS syscall number and open flags (Principle V): O_CREAT is 0x200
// on macOS (0x40 on Linux), so the flag value lives here. BSD signals errors via
// the carry flag; we normalize to a negative return (fd >= 0 / < 0 error).

#include "uolt.inc"

.set SYS_OPEN,       0x2000005
.set O_WRONLY_CREAT, 0x201      // O_WRONLY (1) | O_CREAT (0x200)

.text
.globl sys_create
sys_create:
    mov     rdx, rsi
    mov     rsi, O_WRONLY_CREAT
    mov     rax, SYS_OPEN
    syscall
    jc      1f
    ret
1:
    neg     rax
    ret
