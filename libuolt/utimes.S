// libuolt/utimes.S - internal API: uolt_utimes(path, times).
//
// Thin wrapper over the per-OS sys_utimes (Principle V). rdi = path, rsi = times
// (struct timeval[2], or NULL for the current time); returns 0 or a negative
// errno uniformly.

#include "uolt.inc"

.text
.globl uolt_utimes
uolt_utimes:
    jmp     sys_utimes
