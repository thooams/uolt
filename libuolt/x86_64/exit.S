// libuolt/exit.S - internal API: uolt_exit(status).
//
// First member of the shared libuolt API (Principle V). Tools call uolt_exit
// instead of touching syscalls directly; the OS-specific number lives in
// sys/<os>/exit.S. This is a tail call: status stays in rdi, we jump straight
// to sys_exit so no extra frame or instruction is spent (Principle VII).

#include "uolt.inc"

.text
.globl uolt_exit
uolt_exit:
    jmp     sys_exit            // status in rdi -> sys_exit; never returns
