// libuolt/arm64/statsize.S - internal API: uolt_statsize. Thin tail branch to sys_statsize
// (Principle V, aarch64). Arguments already match the ABI; result stays in x0.

#include "uolt.inc"

.text
.globl uolt_statsize
uolt_statsize:
    b       sys_statsize
