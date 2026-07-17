// libuolt/arm64/create.S - internal API: uolt_create. Thin tail branch to sys_create
// (Principle V, aarch64). Arguments already match the ABI; result stays in x0.

#include "uolt.inc"

.text
.globl uolt_create
uolt_create:
    b       sys_create
