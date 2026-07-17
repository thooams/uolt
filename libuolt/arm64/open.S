// libuolt/arm64/open.S - internal API: uolt_open. Thin tail branch to sys_open
// (Principle V, aarch64). Arguments already match the ABI; result stays in x0.

#include "uolt.inc"

.text
.globl uolt_open
uolt_open:
    b       sys_open
