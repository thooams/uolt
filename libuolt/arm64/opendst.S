// libuolt/arm64/opendst.S - internal API: uolt_opendst. Thin tail branch to sys_opendst
// (Principle V, aarch64). Arguments already match the ABI; result stays in x0.

#include "uolt.inc"

.text
.globl uolt_opendst
uolt_opendst:
    b       sys_opendst
