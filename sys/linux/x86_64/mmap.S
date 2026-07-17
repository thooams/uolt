// sys/linux/mmap.S - Linux anonymous-mapping primitive.
// sys_mmap_anon(size in rdi) -> rax = base address, or -errno. Maps a private,
// zero-filled, read/write region (PROT_READ|PROT_WRITE, MAP_PRIVATE|
// MAP_ANONYMOUS). The pages are committed lazily by the kernel on first touch,
// so a large reservation costs only address space until it is used. Owns the
// syscall number and flag values (Principle V).
#include "uolt.inc"
.set SYS_MMAP, 9
.text
.globl sys_mmap_anon
sys_mmap_anon:
    mov     rsi, rdi                    // length
    xor     edi, edi                    // addr = 0 (kernel chooses)
    mov     edx, 3                      // PROT_READ | PROT_WRITE
    mov     r10, 0x22                   // MAP_PRIVATE | MAP_ANONYMOUS
    mov     r8, -1                      // fd
    xor     r9d, r9d                    // offset
    mov     rax, SYS_MMAP
    syscall
    ret                                 // negative (in -4095..-1) on error
