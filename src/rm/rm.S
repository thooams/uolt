// src/rm/rm.S - the POSIX `rm` utility (files, non-recursive).
//
// rm [-f] file...: remove each named file with unlink. With -f, operands that do
// not exist are ignored silently and it is not an error to have no operands. A
// directory operand is an error (recursive removal, -r/-R, needs directory
// reading and is out of scope in v1). -i (interactive) is not supported.
//
// A failure (other than a missing file under -f) writes a stderr diagnostic and
// sets the exit status to 1, without stopping the remaining operands. No heap
// (Principle IV).
//
// Called as uolt_main(argc in rdi, argv in rsi) by the per-OS entry shim.
//
// Register roles (callee-saved): r12 = operand count, r13 = &argv walk,
//   r14 = exit status, r15 = -f flag, rbx = current path.

#include "uolt.inc"

.set STDERR, 2
.set ENOENT, 2

.text
.globl uolt_main
uolt_main:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    mov     r12, rdi
    dec     r12
    lea     r13, [rsi + 8]
    xor     r14, r14
    xor     r15, r15            // -f flag

.opt:
    test    r12, r12
    jz      .after
    mov     rbx, [r13]
    cmp     byte ptr [rbx], '-'
    jne     .after
    cmp     byte ptr [rbx + 1], 0
    je      .after
    cmp     byte ptr [rbx + 1], '-'
    je      .maybe_ddash
    lea     rdi, [rbx + 1]      // validate letters (only 'f')
    mov     rsi, rdi
.v:
    movzx   eax, byte ptr [rdi]
    test    al, al
    jz      .apply
    cmp     al, 'f'
    je      1f
    jmp     .after              // unknown -> treat as an operand
1:
    inc     rdi
    jmp     .v
.apply:
    mov     r15, 1              // -f (only 'f' is valid here)
    add     r13, 8
    dec     r12
    jmp     .opt
.maybe_ddash:
    cmp     byte ptr [rbx + 2], 0
    jne     .after
    add     r13, 8
    dec     r12
.after:
    test    r12, r12
    jnz     .loop
    // no operands: -f makes it a no-op, otherwise a usage error
    test    r15, r15
    jnz     .fin
    jmp     .usage

.loop:
    test    r12, r12
    jz      .fin
    mov     rbx, [r13]
    mov     rdi, rbx
    call    uolt_unlink
    test    rax, rax
    jns     .next
    // error: under -f a missing file is fine; anything else diagnoses
    cmp     rax, -ENOENT
    jne     .diag
    test    r15, r15
    jnz     .next               // -f + ENOENT -> ignore
.diag:
    mov     r14, 1
    lea     rdi, [rip + err_pre]
    call    err_puts
    mov     rdi, rbx
    call    err_puts
    lea     rdi, [rip + err_suf]
    call    err_puts
.next:
    add     r13, 8
    dec     r12
    jmp     .loop

.fin:
    mov     eax, r14d
    jmp     .ret
.usage:
    lea     rdi, [rip + err_usage]
    call    err_puts
    mov     eax, 1
.ret:
    pop     r15
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

err_usage: .asciz "uolt-rm: usage: rm [-f] file...\n"
err_pre:   .asciz "uolt-rm: "
err_suf:   .asciz ": cannot remove\n"
