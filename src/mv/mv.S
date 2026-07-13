// src/mv/mv.S - the POSIX `mv` utility (two-operand rename form).
//
// mv source target: rename `source` to `target` with the rename syscall, which
// atomically replaces an existing target file. Moving several sources into a
// directory (mv src... dir) is out of scope in v1: it needs a directory check
// (stat). Cross-device moves (rename -> EXDEV) are not handled either.
//
// A failure yields a stderr diagnostic and exit 1. No heap (Principle IV).
//
// Called as uolt_main(argc in rdi, argv in rsi) by the per-OS entry shim.
//
// Register roles (callee-saved): r12 = operand count, r13 = &argv walk,
//   r14 = exit status, rbx = source.

#include "uolt.inc"

.set STDERR, 2

.text
.globl uolt_main
uolt_main:
    push    rbx
    push    r12
    push    r13
    push    r14

    mov     r12, rdi
    dec     r12
    lea     r13, [rsi + 8]
    xor     r14, r14

    // Only "--" is recognized as an option here (mv has no v1 flags).
    test    r12, r12
    jz      .usage
    mov     rbx, [r13]
    cmp     byte ptr [rbx], '-'
    jne     .after
    cmp     byte ptr [rbx + 1], '-'
    jne     .after
    cmp     byte ptr [rbx + 2], 0
    jne     .after
    add     r13, 8              // "--"
    dec     r12
.after:
    cmp     r12, 2
    jne     .usage              // exactly two operands in v1

    mov     rdi, [r13]          // source
    mov     rsi, [r13 + 8]      // target
    mov     rbx, rdi
    call    uolt_rename
    test    rax, rax
    jns     .fin
    mov     r14, 1
    lea     rdi, [rip + err_pre]
    call    err_puts
    mov     rdi, rbx
    call    err_puts
    lea     rdi, [rip + err_suf]
    call    err_puts

.fin:
    mov     eax, r14d
    jmp     .ret
.usage:
    lea     rdi, [rip + err_usage]
    call    err_puts
    mov     eax, 1
.ret:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

err_puts:
    mov     r8, rdi
    call    uolt_strlen
    mov     rdx, rax
    mov     rsi, r8
    mov     rdi, STDERR
    jmp     uolt_write

err_usage: .asciz "uolt-mv: usage: mv source target\n"
err_pre:   .asciz "uolt-mv: "
err_suf:   .asciz ": cannot move\n"
