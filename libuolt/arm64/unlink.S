// libuolt/arm64/unlink.S - internal API: uolt_unlink. Thin tail branch to sys_unlink
// (Principle V, aarch64). Arguments already match the ABI; result stays in x0.

#include "uolt.inc"

.text
.globl uolt_unlink
uolt_unlink:
    b       sys_unlink
