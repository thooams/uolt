// libuolt/arm64/exit.S - internal API: uolt_exit(status).
//
// First member of the shared libuolt API (Principle V). Tools call uolt_exit
// instead of touching syscalls directly; the OS/arch-specific number lives in
// sys/linux/arm64/exit.S. This is a tail branch: status stays in x0, we jump
// straight to sys_exit so no extra frame or instruction is spent (Principle VII).

#include "uolt.inc"

.text
.globl uolt_exit
uolt_exit:
    b       sys_exit            // status in x0 -> sys_exit; never returns
