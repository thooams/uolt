// libuolt/arm64/rename.S - internal API: uolt_rename. Thin tail branch to sys_rename
// (Principle V, aarch64). Arguments already match the ABI; result stays in x0.

#include "uolt.inc"

.text
.globl uolt_rename
uolt_rename:
    b       sys_rename
