// libuolt/arm64/umask.S - internal API: uolt_umask. Thin tail branch to sys_umask
// (Principle V, aarch64). Arguments already match the ABI; result stays in x0.

#include "uolt.inc"

.text
.globl uolt_umask
uolt_umask:
    b       sys_umask
