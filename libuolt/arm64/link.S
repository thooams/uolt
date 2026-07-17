// libuolt/arm64/link.S - internal API: uolt_link. Thin tail branch to sys_link
// (Principle V, aarch64). Arguments already match the ABI; result stays in x0.

#include "uolt.inc"

.text
.globl uolt_link
uolt_link:
    b       sys_link
