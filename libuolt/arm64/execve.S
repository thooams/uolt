// libuolt/arm64/execve.S - internal API: uolt_execve. Thin tail branch to sys_execve
// (Principle V, aarch64). Arguments already match the ABI; result stays in x0.

#include "uolt.inc"

.text
.globl uolt_execve
uolt_execve:
    b       sys_execve
