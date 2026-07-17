// libuolt/arm64/getdents.S - internal API: uolt_getdents. Thin tail branch to sys_getdents
// (Principle V, aarch64). Arguments already match the ABI; result stays in x0.

#include "uolt.inc"

.text
.globl uolt_getdents
uolt_getdents:
    b       sys_getdents
