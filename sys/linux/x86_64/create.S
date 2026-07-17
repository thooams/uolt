// sys/linux/create.S - Linux x86_64 "open for create" primitive.
//
// sys_create(path in rdi, mode in rsi) -> fd: open the path O_WRONLY|O_CREAT
// (creating it if missing, mode applied through the umask), returning a
// descriptor (>= 0) or a negative errno. Owns both the syscall number and the
// OS-specific open flags (Principle V) - O_CREAT differs between Linux and macOS,
// which is exactly why this lives behind a per-OS wrapper.

#include "uolt.inc"

.set SYS_OPEN,      2
.set O_WRONLY_CREAT, 0x41       // O_WRONLY (1) | O_CREAT (0x40)

.text
.globl sys_create
sys_create:
    mov     rdx, rsi            // mode -> 3rd open arg
    mov     rsi, O_WRONLY_CREAT
    mov     rax, SYS_OPEN
    syscall
    ret
