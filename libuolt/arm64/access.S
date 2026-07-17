// libuolt/arm64/access.S - internal API: uolt_access. Thin tail branch to sys_access
// (Principle V, aarch64). Arguments already match the ABI; result stays in x0.

#include "uolt.inc"

.text
.globl uolt_access
uolt_access:
    b       sys_access
