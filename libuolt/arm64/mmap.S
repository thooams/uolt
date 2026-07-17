// libuolt/arm64/mmap.S - internal API: uolt_mmap_anon. Thin tail branch to sys_mmap_anon
// (Principle V, aarch64). Arguments already match the ABI; result stays in x0.

#include "uolt.inc"

.text
.globl uolt_mmap_anon
uolt_mmap_anon:
    b       sys_mmap_anon
