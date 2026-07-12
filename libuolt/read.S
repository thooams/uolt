// libuolt/read.S - internal API: uolt_read(fd, buf, len) -> count.
//
// Thin wrapper over the per-OS sys_read (Principle V). Arguments already match
// the read ABI (rdi=fd, rsi=buf, rdx=len), so this is a tail call; the result
// stays in rax: bytes read (0 at EOF) or a negative errno on error.

#include "uolt.inc"

.text
.globl uolt_read
uolt_read:
    jmp     sys_read
