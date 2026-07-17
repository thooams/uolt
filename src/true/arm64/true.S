// src/true/arm64/true.S - uolt-true: the POSIX `true` utility (aarch64).
//
// Behavior: ignore all arguments, read/write nothing, always succeed.
// (spec FR-001..FR-007). The per-arch entry shim (sys/linux/arm64/start.S) calls
// uolt_main and exits with the status it returns; here that status is simply 0.
// No I/O, no heap. Mirrors the x86_64 body.

#include "uolt.inc"

.text
.globl uolt_main
uolt_main:
    mov     x0, EXIT_SUCCESS    // return success; the start shim calls uolt_exit
    ret
