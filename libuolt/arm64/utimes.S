// libuolt/arm64/utimes.S - internal API: uolt_utimes. Thin tail branch to sys_utimes
// (Principle V, aarch64). Arguments already match the ABI; result stays in x0.

#include "uolt.inc"

.text
.globl uolt_utimes
uolt_utimes:
    b       sys_utimes
