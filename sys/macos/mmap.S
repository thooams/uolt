// sys/macos/mmap.S - macOS anonymous-mapping primitive.
// sys_mmap_anon(size in rdi) -> rax = base address, or -errno. Maps a private,
// zero-filled, read/write region (PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANON).
// On error macOS sets the carry flag and returns errno; negate so callers branch
// on sign. Owns the syscall number and flag values (Principle V).
#include "uolt.inc"
.set SYS_MMAP, 0x20000C5
.text
.globl sys_mmap_anon
sys_mmap_anon:
    mov     rsi, rdi                    // length
    xor     edi, edi                    // addr = 0
    mov     edx, 3                      // PROT_READ | PROT_WRITE
    mov     r10, 0x1002                 // MAP_PRIVATE | MAP_ANON
    mov     r8, -1                      // fd
    xor     r9d, r9d                    // offset
    mov     rax, SYS_MMAP
    syscall
    jc      1f
    ret
1:
    neg     rax
    ret
