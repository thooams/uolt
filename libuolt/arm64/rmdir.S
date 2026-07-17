// libuolt/arm64/rmdir.S - internal API: uolt_rmdir. Thin tail branch to sys_rmdir
// (Principle V, aarch64). Arguments already match the ABI; result stays in x0.

#include "uolt.inc"

.text
.globl uolt_rmdir
uolt_rmdir:
    b       sys_rmdir
