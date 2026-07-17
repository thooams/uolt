// src/false/arm64/false.S - uolt-false: the POSIX `false` utility (aarch64).
//
// Mirror of uolt-true: ignore all arguments, no I/O, always return a non-zero
// status (1). The per-arch entry shim (sys/linux/arm64/start.S) calls uolt_main
// and exits with the status it returns.

#include "uolt.inc"

.text
.globl uolt_main
uolt_main:
    mov     x0, EXIT_FAILURE    // return failure; the start shim calls uolt_exit
    ret
