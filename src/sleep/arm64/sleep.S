// src/sleep/arm64/sleep.S - the `sleep` utility (aarch64).
//
// sleep time...: suspend for the sum of the operands, then exit 0. Each operand
// is a non-negative decimal with an optional fractional part and an optional unit
// suffix s/m/h/d (default s). Durations accumulate in nanoseconds, split into
// sec+nsec, and pass to uolt_sleep (nanosleep on Linux). No heap (Principle IV).
// Bad/absent operand -> stderr diagnostic, exit 1. Mirrors the x86_64 body.
//
// Callee-saved roles: x19 = remaining operand count, x20 = &argv walk,
//   x21 = total nanoseconds. parse_dur/err_puts are helpers.

#include "uolt.inc"

.set STDERR, 2

.text
.globl uolt_main
uolt_main:
    stp     x29, x30, [sp, #-48]!
    stp     x19, x20, [sp, #16]
    str     x21, [sp, #32]

    sub     x19, x0, #1                 // operand count
    add     x20, x1, #8                 // &argv[1]
    mov     x21, #0                     // total nanoseconds
    cbz     x19, .Lusage                // no operand

.Lparse_loop:
    cbz     x19, .Ldo_sleep
    ldr     x0, [x20]
    bl      parse_dur                   // x0 = ns, x1 = 0 ok / 1 error
    cbnz    x1, .Lbad
    add     x21, x21, x0
    add     x20, x20, #8
    sub     x19, x19, #1
    b       .Lparse_loop

.Ldo_sleep:
    movz    x2, #0xCA00                 // NS_PER_S = 1e9 = 0x3B9ACA00
    movk    x2, #0x3B9A, lsl #16
    udiv    x1, x21, x2                 // sec
    msub    x3, x1, x2, x21             // nsec = total - sec*1e9
    mov     x0, x1                      // sec
    mov     x1, x3                      // nsec
    bl      uolt_sleep
    mov     x0, #0
    b       .Lret

.Lbad:
    adr     x0, err_bad
    bl      err_puts
    mov     x0, #1
    b       .Lret
.Lusage:
    adr     x0, err_usage
    bl      err_puts
    mov     x0, #1
.Lret:
    ldr     x21, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

// parse_dur(x0 = ASCIZ) -> x0 = nanoseconds, x1 = 0 (ok) / 1 (error). Accepts
// digits, one optional '.', up to 9 fractional digits, and one trailing unit
// suffix s/m/h/d. Uses only caller-saved regs (x2..x11); makes no calls.
parse_dur:
    mov     x2, x0                      // cursor
    mov     x4, #0                      // integer seconds
    mov     x5, #0                      // fractional nanoseconds
    mov     x6, #0                      // digit-seen flag
    mov     x11, #10
.Lpd_pi:
    ldrb    w3, [x2]
    sub     w7, w3, #'0'
    cmp     w7, #9
    b.hi    .Lpd_pi_done                // not a digit (or NUL)
    mul     x4, x4, x11
    add     x4, x4, w7, uxtw
    mov     x6, #1
    add     x2, x2, #1
    b       .Lpd_pi
.Lpd_pi_done:
    cmp     w3, #'.'
    b.ne    .Lpd_suffix
    add     x2, x2, #1                  // fractional part
    movz    x9, #0xE100                 // weight of first frac digit = 1e8 = 0x05F5E100
    movk    x9, #0x05F5, lsl #16
.Lpd_pf:
    ldrb    w3, [x2]
    sub     w7, w3, #'0'
    cmp     w7, #9
    b.hi    .Lpd_suffix
    mov     x6, #1
    mul     x8, x7, x9                  // digit * weight
    add     x5, x5, x8
    udiv    x9, x9, x11                 // weight /= 10 (reaches 0 past 9 digits)
    add     x2, x2, #1
    b       .Lpd_pf
.Lpd_suffix:
    cbz     x6, .Lpd_err                // no digits at all
    ldrb    w3, [x2]
    cbz     w3, .Lpd_mult1              // no suffix -> seconds
    ldrb    w8, [x2, #1]
    cbnz    w8, .Lpd_err                // a suffix must be the last character
    mov     x8, #1
    cmp     w3, #'s'
    b.eq    .Lpd_apply
    mov     x8, #60
    cmp     w3, #'m'
    b.eq    .Lpd_apply
    movz    x8, #3600
    cmp     w3, #'h'
    b.eq    .Lpd_apply
    movz    x8, #0x5180                 // 86400 = 0x00015180
    movk    x8, #0x0001, lsl #16
    cmp     w3, #'d'
    b.eq    .Lpd_apply
    b       .Lpd_err
.Lpd_mult1:
    mov     x8, #1
.Lpd_apply:
    mul     x4, x4, x8                  // (sec * mult)
    movz    x9, #0xCA00                 // * 1e9
    movk    x9, #0x3B9A, lsl #16
    mul     x4, x4, x9
    mul     x5, x5, x8                  // + frac_ns * mult
    add     x0, x4, x5
    mov     x1, #0
    ret
.Lpd_err:
    mov     x0, #0
    mov     x1, #1
    ret

// err_puts(x0 = ASCIZ) -> stderr; length via strlen. Saves lr (calls strlen).
err_puts:
    stp     x29, x30, [sp, #-16]!
    mov     x3, x0
    bl      uolt_strlen
    mov     x2, x0
    mov     x1, x3
    mov     x0, #STDERR
    bl      uolt_write
    ldp     x29, x30, [sp], #16
    ret

err_usage: .asciz "uolt-sleep: usage: sleep time...\n"
err_bad:   .asciz "uolt-sleep: invalid time interval\n"
