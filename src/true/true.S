// src/true/true.S - uolt-true: the POSIX `true` utility.
//
// Behavior: ignore all arguments, read/write nothing, always exit 0.
// (spec FR-001..FR-007). The kernel places argc/argv on the stack at _start;
// we deliberately ignore them. No I/O, no heap, one syscall (exit).
//
// Entry symbol is _start on both Linux and macOS (the linker entry is set with
// -e _start); it contains no OS-specific syscall number - that is in
// sys/<os>/exit.S, reached via the libuolt uolt_exit entry point.

#include "uolt.inc"

.text
.globl _start
_start:
    mov     rdi, EXIT_SUCCESS   // status 0 in the first syscall-argument register
    call    uolt_exit           // libuolt -> sys_exit -> exit syscall; never returns
