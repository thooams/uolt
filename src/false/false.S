// src/false/false.S - uolt-false: the POSIX `false` utility.
//
// Mirror of uolt-true: ignore all arguments, no I/O, always return a non-zero
// status (1). The per-OS entry shim (sys/<os>/start.S) calls uolt_main and exits
// with the status it returns.

#include "uolt.inc"

.text
.globl uolt_main
uolt_main:
    mov     rax, EXIT_FAILURE   // return failure; the start shim calls uolt_exit
    ret
