// src/sleep/sleep.S - the `sleep` utility.
//
// sleep time...: suspend execution for the sum of the time operands, then exit
// 0. Each operand is a non-negative decimal (with an optional fractional part)
// and an optional single-letter unit suffix: s (seconds, the default), m
// (minutes), h (hours), or d (days) - the common GNU form; POSIX requires only
// an integer number of seconds, which is the no-suffix case. An invalid operand,
// or none at all, is an error (stderr diagnostic, exit 1).
//
// Durations are accumulated in nanoseconds, split into seconds + nanoseconds,
// and passed to uolt_sleep - whose per-OS backend is nanosleep on Linux and
// select on macOS (which has no direct nanosleep syscall). No heap (Principle IV).
//
// Called as uolt_main(argc in rdi, argv in rsi) by the per-OS entry shim.
//
// uolt_main register roles (callee-saved):
//   r12 = remaining operand count, r13 = &argv walk, r15 = total nanoseconds

#include "uolt.inc"

.set STDERR,   2
.set NS_PER_S, 1000000000

.text
.globl uolt_main
uolt_main:
    push    rbx
    push    r12
    push    r13
    push    r15

    mov     r12, rdi
    dec     r12                 // operand count
    lea     r13, [rsi + 8]      // &argv[1]
    xor     r15, r15            // total nanoseconds

    test    r12, r12
    jz      .usage              // no operand

.parse_loop:
    test    r12, r12
    jz      .do_sleep
    mov     rdi, [r13]
    call    parse_dur           // rax = ns, rdx = 0 ok / 1 error
    test    rdx, rdx
    jnz     .bad
    add     r15, rax
    add     r13, 8
    dec     r12
    jmp     .parse_loop

.do_sleep:
    // Split total ns into seconds + nanoseconds and sleep.
    mov     rax, r15
    xor     rdx, rdx
    mov     rcx, NS_PER_S
    div     rcx                 // rax = sec, rdx = nsec
    mov     rdi, rax
    mov     rsi, rdx
    call    uolt_sleep
    xor     eax, eax
    jmp     .ret

.bad:
    lea     rdi, [rip + err_bad]
    call    err_puts
    mov     eax, 1
    jmp     .ret
.usage:
    lea     rdi, [rip + err_usage]
    call    err_puts
    mov     eax, 1
.ret:
    pop     r15
    pop     r13
    pop     r12
    pop     rbx
    ret

// parse_dur(rdi = ASCIZ) -> rax = nanoseconds, rdx = 0 (ok) / 1 (error).
// Accepts digits, one optional '.', a fractional part (up to 9 digits used), and
// an optional single unit suffix s/m/h/d at the very end.
parse_dur:
    push    rbx
    push    r12
    push    r13
    xor     r12, r12            // integer seconds
    xor     r13, r13            // fractional nanoseconds (< 1e9)
    xor     rbx, rbx            // digit-seen flag
.pi:
    movzx   rcx, byte ptr [rdi]
    mov     rax, rcx
    sub     al, '0'
    cmp     al, 9
    ja      .pi_done            // not a digit
    imul    r12, r12, 10
    movzx   rax, al
    add     r12, rax
    mov     rbx, 1
    inc     rdi
    jmp     .pi
.pi_done:
    cmp     cl, '.'
    jne     .suffix
    inc     rdi                 // fractional part
    mov     r9, 100000000       // 10^8: weight of the first fractional digit
.pf:
    movzx   rcx, byte ptr [rdi]
    mov     rax, rcx
    sub     al, '0'
    cmp     al, 9
    ja      .suffix
    mov     rbx, 1
    movzx   rax, al
    imul    rax, r9
    add     r13, rax
    mov     rax, r9             // r9 /= 10 (reaches 0 past 9 digits)
    xor     rdx, rdx
    mov     rcx, 10
    div     rcx
    mov     r9, rax
    inc     rdi
    jmp     .pf
.suffix:
    test    rbx, rbx
    jz      .err                // no digits at all
    movzx   rcx, byte ptr [rdi]
    test    cl, cl
    jz      .mult_1             // no suffix -> seconds
    cmp     byte ptr [rdi + 1], 0
    jne     .err                // a suffix must be the last character
    mov     r8, 1
    cmp     cl, 's'
    je      .apply
    mov     r8, 60
    cmp     cl, 'm'
    je      .apply
    mov     r8, 3600
    cmp     cl, 'h'
    je      .apply
    mov     r8, 86400
    cmp     cl, 'd'
    je      .apply
    jmp     .err
.mult_1:
    mov     r8, 1
.apply:
    mov     rax, r12            // (sec * mult) * 1e9
    imul    rax, r8
    mov     rcx, NS_PER_S
    imul    rax, rcx
    mov     rdx, r13            // + frac_ns * mult
    imul    rdx, r8
    add     rax, rdx
    xor     rdx, rdx            // ok
    jmp     .pret
.err:
    xor     rax, rax
    mov     rdx, 1
.pret:
    pop     r13
    pop     r12
    pop     rbx
    ret

// err_puts(rdi = ASCIZ) -> stderr; length via strlen.
err_puts:
    mov     r8, rdi
    call    uolt_strlen
    mov     rdx, rax
    mov     rsi, r8
    mov     rdi, STDERR
    jmp     uolt_write

err_usage: .asciz "uolt-sleep: usage: sleep time...\n"
err_bad:   .asciz "uolt-sleep: invalid time interval\n"
