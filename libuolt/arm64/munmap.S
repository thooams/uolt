// libuolt/arm64/munmap.S - internal API: uolt_munmap. Thin tail branch to sys_munmap
// (Principle V, aarch64). Arguments already match the ABI; result stays in x0.

#include "uolt.inc"

.text
.globl uolt_munmap
uolt_munmap:
    b       sys_munmap
