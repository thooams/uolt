// libuolt/arm64/lseek.S - internal API: uolt_lseek. Thin tail branch to sys_lseek
// (Principle V, aarch64). Arguments already match the ABI; result stays in x0.

#include "uolt.inc"

.text
.globl uolt_lseek
uolt_lseek:
    b       sys_lseek
