// sys/linux/arm64/exit.S - Linux aarch64 `exit` syscall wrapper.
//
// Owns the Linux aarch64 syscall number so no tool or libuolt code names it
// (Principle V). Callers put the status in x0 and call sys_exit; this never
// returns. AArch64 passes the syscall number in x8 and traps with `svc #0`.
// We mirror the x86_64 wrapper's choice of the plain exit(2) call (single
// -threaded process, so exit and exit_group are equivalent here).

#include "uolt.inc"

// Linux aarch64 syscall number for exit(2). (exit_group is 94, unused here.)
.set SYS_EXIT, 93

.text
.globl sys_exit
sys_exit:
    mov     x8, SYS_EXIT        // syscall number -> x8
    svc     #0                  // status already in x0 from the caller; does not return
