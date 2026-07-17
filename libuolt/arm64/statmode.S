// libuolt/arm64/statmode.S - internal API: uolt_statmode. Thin tail branch to sys_statmode
// (Principle V, aarch64). Arguments already match the ABI; result stays in x0.

#include "uolt.inc"

.text
.globl uolt_statmode
uolt_statmode:
    b       sys_statmode
