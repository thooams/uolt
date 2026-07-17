// sys/linux/arm64/mmap.S - Linux anonymous-mapping primitive (aarch64).
// sys_mmap_anon(size in x0) -> x0 = base address, or -errno. Private, zero-filled
// PROT_READ|PROT_WRITE mapping; pages committed lazily. Owns the number+flags
// (Principle V). mmap args: x0=addr x1=len x2=prot x3=flags x4=fd x5=off.
#include "uolt.inc"
.set SYS_MMAP, 222
.text
.globl sys_mmap_anon
sys_mmap_anon:
    mov     x1, x0                      // len = requested size
    mov     x0, #0                      // addr = 0 (kernel chooses)
    mov     x2, #3                      // PROT_READ | PROT_WRITE
    mov     x3, #0x22                   // MAP_PRIVATE | MAP_ANONYMOUS
    mov     x4, #-1                     // fd = -1
    mov     x5, #0                      // offset = 0
    mov     x8, SYS_MMAP
    svc     #0
    ret                                 // negative (in -4095..-1) on error
