// libuolt/arm64/read.S - internal API: uolt_read. Thin tail branch to sys_read
// (Principle V, aarch64). Arguments already match the ABI; result stays in x0.

#include "uolt.inc"

.text
.globl uolt_read
uolt_read:
    b       sys_read
