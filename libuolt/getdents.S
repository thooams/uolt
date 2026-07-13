// libuolt/getdents.S - internal API: uolt_getdents(fd, buf, count) -> bytes.
//
// Thin wrapper over the per-OS sys_getdents (Principle V): Linux getdents64,
// macOS getdirentries64. rdi = fd, rsi = buf, rdx = count; returns the number of
// bytes of directory records written (0 at end) or a negative errno. Records use
// the DIRENT_* offsets from uolt.inc.

#include "uolt.inc"

.text
.globl uolt_getdents
uolt_getdents:
    jmp     sys_getdents
