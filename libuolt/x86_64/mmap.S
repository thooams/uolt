// libuolt/mmap.S - internal API: uolt_mmap_anon(size) -> base / -errno.
// Thin wrapper over the per-OS sys_mmap_anon (Principle V). Used by tools that
// must hold an unbounded amount of input at once (e.g. sort) to avoid a fixed
// buffer that would silently truncate; it is an explicit, failure-checked
// reservation, not a hidden heap (Principle IV allows mmap when justified).
#include "uolt.inc"
.text
.globl uolt_mmap_anon
uolt_mmap_anon:
    jmp     sys_mmap_anon
