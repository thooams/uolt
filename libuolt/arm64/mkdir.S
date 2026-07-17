// libuolt/arm64/mkdir.S - internal API: uolt_mkdir. Thin tail branch to sys_mkdir
// (Principle V, aarch64). Arguments already match the ABI; result stays in x0.

#include "uolt.inc"

.text
.globl uolt_mkdir
uolt_mkdir:
    b       sys_mkdir
