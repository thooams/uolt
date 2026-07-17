// libuolt/arm64/opendir.S - internal API: uolt_opendir. Thin tail branch to sys_opendir
// (Principle V, aarch64). Arguments already match the ABI; result stays in x0.

#include "uolt.inc"

.text
.globl uolt_opendir
uolt_opendir:
    b       sys_opendir
