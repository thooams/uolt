// libuolt/arm64/lstatmode.S - internal API: uolt_lstatmode. Thin tail branch to sys_lstatmode
// (Principle V, aarch64). Arguments already match the ABI; result stays in x0.

#include "uolt.inc"

.text
.globl uolt_lstatmode
uolt_lstatmode:
    b       sys_lstatmode
