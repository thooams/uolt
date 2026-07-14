// src/env/env.S - the `env` utility (print the environment).
//
// env: with no operand, print each environment variable ("NAME=value") on its
// own line. Running a command with a modified environment (env [NAME=value...]
// command) needs execve and is out of scope in v1; any operands are ignored and
// the environment is printed.
//
// The environment array follows argv in memory: after argv[argc] (the NULL
// terminator) come the environment pointers, NULL-terminated. So envp is
// argv + (argc + 1) * 8 on both Linux (stack layout) and macOS (LC_MAIN passes
// the same block), which lets this work without touching the entry shim.
//
// Called as uolt_main(argc in rdi, argv in rsi) by the per-OS entry shim.

#include "uolt.inc"

.set STDOUT, 1

.text
.globl uolt_main
uolt_main:
    push    rbx
    push    r12

    // envp = argv + (argc + 1) * 8
    lea     rbx, [rsi + rdi*8 + 8]
.loop:
    mov     r12, [rbx]                  // envp[i]
    test    r12, r12
    jz      .done                       // NULL terminator
    mov     rdi, r12
    call    uolt_strlen
    mov     rdx, rax
    mov     rsi, r12
    mov     rdi, STDOUT
    call    uolt_write
    mov     rdi, STDOUT
    lea     rsi, [rip + nl_char]
    mov     rdx, 1
    call    uolt_write
    add     rbx, 8
    jmp     .loop
.done:
    xor     eax, eax
    pop     r12
    pop     rbx
    ret

nl_char: .byte 0x0a
