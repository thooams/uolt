// libuolt/open.S - internal API: uolt_open(path, flags, mode) -> fd.
//
// Thin wrapper over the per-OS sys_open (Principle V). Arguments already match
// the open ABI (rdi=path, rsi=flags, rdx=mode), so this is a tail call; the
// result stays in rax: a descriptor (>= 0) on success or a negative errno on
// error, uniform across Linux and macOS.

#include "uolt.inc"

.text
.globl uolt_open
uolt_open:
    jmp     sys_open
