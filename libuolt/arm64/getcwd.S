// libuolt/arm64/getcwd.S - internal API: uolt_getcwd. Thin tail branch to sys_getcwd
// (Principle V, aarch64). Arguments already match the ABI; result stays in x0.

#include "uolt.inc"

.text
.globl uolt_getcwd
uolt_getcwd:
    b       sys_getcwd
