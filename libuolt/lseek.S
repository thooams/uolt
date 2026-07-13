// libuolt/lseek.S - internal API: uolt_lseek(fd, offset, whence) -> offset.
//
// Thin wrapper over the per-OS sys_lseek (Principle V). Arguments already match
// the lseek ABI (rdi=fd, rsi=offset, rdx=whence), so this is a tail call; the
// result stays in rax: the new absolute offset (>= 0) or a negative errno on
// error (notably -ESPIPE for a non-seekable descriptor).

#include "uolt.inc"

.text
.globl uolt_lseek
uolt_lseek:
    jmp     sys_lseek
