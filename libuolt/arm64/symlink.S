// libuolt/arm64/symlink.S - internal API: uolt_symlink. Thin tail branch to sys_symlink
// (Principle V, aarch64). Arguments already match the ABI; result stays in x0.

#include "uolt.inc"

.text
.globl uolt_symlink
uolt_symlink:
    b       sys_symlink
