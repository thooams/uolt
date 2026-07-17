// libuolt/arm64/close.S - internal API: uolt_close. Thin tail branch to sys_close
// (Principle V, aarch64). Arguments already match the ABI; result stays in x0.

#include "uolt.inc"

.text
.globl uolt_close
uolt_close:
    b       sys_close
