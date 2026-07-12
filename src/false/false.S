// src/false/false.S - uolt-false: the POSIX `false` utility.
//
// Behavior: ignore all arguments, read/write nothing, always exit with a
// non-zero status (1). It is the mirror of uolt-true and shares the exact same
// scaffolding; only the exit status differs (EXIT_FAILURE vs EXIT_SUCCESS).
//
// Entry symbol is _start on both Linux and macOS (linker entry set with
// -e _start). No OS-specific syscall number here - that lives in
// sys/<os>/exit.S, reached via the libuolt uolt_exit entry point.

#include "uolt.inc"

.text
.globl _start
_start:
    mov     rdi, EXIT_FAILURE   // status 1 in the first syscall-argument register
    call    uolt_exit           // libuolt -> sys_exit -> exit syscall; never returns
