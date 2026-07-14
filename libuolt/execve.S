// libuolt/execve.S - internal API: uolt_execve(path, argv, envp).
//
// Thin wrapper over the per-OS sys_execve (Principle V). Arguments already match
// the execve ABI (rdi=path, rsi=argv, rdx=envp), so this is a tail call. It does
// not return on success; on failure the result is a negative errno in rax.

#include "uolt.inc"

.text
.globl uolt_execve
uolt_execve:
    jmp     sys_execve
