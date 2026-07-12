// src/true/true.S - uolt-true: the POSIX `true` utility.
//
// Behavior: ignore all arguments, read/write nothing, always succeed.
// (spec FR-001..FR-007). The per-OS entry shim (sys/<os>/start.S) calls
// uolt_main and exits with the status it returns; here that status is simply 0.
// No I/O, no heap.

#include "uolt.inc"

.text
.globl uolt_main
uolt_main:
    mov     rax, EXIT_SUCCESS   // return success; the start shim calls uolt_exit
    ret
