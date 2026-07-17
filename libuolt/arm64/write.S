// libuolt/arm64/write.S - internal API: uolt_write(fd, buf, len).
//
// Thin wrapper so tools use the libuolt API instead of naming a syscall
// (Principle V). Arguments already match the write ABI (x0=fd, x1=buf, x2=len),
// so this is a tail branch to the per-arch sys_write; result stays in x0.

#include "uolt.inc"

.text
.globl uolt_write
uolt_write:
    b       sys_write
