// libuolt/arm64/sleep.S - internal API: uolt_sleep. Thin tail branch to sys_sleep
// (Principle V, aarch64). Arguments already match the ABI; result stays in x0.

#include "uolt.inc"

.text
.globl uolt_sleep
uolt_sleep:
    b       sys_sleep
