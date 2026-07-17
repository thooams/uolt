// libuolt/arm64/openapp.S - internal API: uolt_openapp. Thin tail branch to sys_openapp
// (Principle V, aarch64). Arguments already match the ABI; result stays in x0.

#include "uolt.inc"

.text
.globl uolt_openapp
uolt_openapp:
    b       sys_openapp
