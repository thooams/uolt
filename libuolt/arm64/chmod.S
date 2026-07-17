// libuolt/arm64/chmod.S - internal API: uolt_chmod. Thin tail branch to sys_chmod
// (Principle V, aarch64). Arguments already match the ABI; result stays in x0.

#include "uolt.inc"

.text
.globl uolt_chmod
uolt_chmod:
    b       sys_chmod
