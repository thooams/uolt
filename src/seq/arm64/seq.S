// src/seq/arm64/seq.S - the `seq` utility (integers), aarch64.
//
// seq [-s STRING] [-w] [first [incr]] last: print the integer sequence from
// first to last stepping by incr. Defaults first=1, incr=1, one per line. -s sets
// the separator; -w zero-pads to the widest term. Negative incr counts down.
// Numbers are formatted into a small stack buffer (no heap, Principle IV). Bad
// operand / zero incr / wrong count -> stderr diagnostic, exit 1. Mirrors the
// x86_64 body; x86 `div` becomes aarch64 `udiv`/`msub`.
//
// Callee-saved roles: x19=first, x20=incr, x21=last, x22=running value,
//   x23=argv walk (later scratch), x24=operand count. Frame locals + number
//   buffer are addressed off x29.

#include "uolt.inc"

.set STDOUT, 1
.set STDERR, 2

.set L_SEP,    64               // separator pointer
.set L_SEPLEN, 72               // separator length
.set L_WIDTH,  80               // pad width (0 = no -w)
.set L_FIRST,  88               // 1 until the first number is emitted
.set NUMEND,   128              // offset of one-past-number-buffer from x29
.set NLBYTE,   96               // a spare stack byte for the trailing newline

.text
.globl uolt_main
uolt_main:
    stp     x29, x30, [sp, #-160]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]

    add     x23, x1, #8                 // &argv[1]
    sub     x24, x0, #1                 // operand count

    adr     x9, nl                      // default separator "\n"
    str     x9, [x29, #L_SEP]
    mov     x9, #1
    str     x9, [x29, #L_SEPLEN]
    str     xzr, [x29, #L_WIDTH]

.Lopt:
    cbz     x24, .Lparsed
    ldr     x0, [x23]
    ldrb    w1, [x0]
    cmp     w1, #'-'
    b.ne    .Lparsed
    ldrb    w1, [x0, #1]
    cbz     w1, .Lparsed                // "-" alone is not an option
    cmp     w1, #'w'
    b.eq    .Lopt_w
    cmp     w1, #'s'
    b.eq    .Lopt_s
    cmp     w1, #'-'
    b.eq    .Lopt_ddash
    sub     w1, w1, #'0'                // '-' before a digit -> negative operand
    cmp     w1, #9
    b.ls    .Lparsed
    b       .Lusage
.Lopt_w:
    ldrb    w1, [x0, #2]
    cbnz    w1, .Lusage
    mov     x9, #1                      // sentinel; real width set later
    str     x9, [x29, #L_WIDTH]
    add     x23, x23, #8
    sub     x24, x24, #1
    b       .Lopt
.Lopt_s:
    add     x0, x0, #2                  // "-sSEP" attached, or "-s" then next arg
    ldrb    w1, [x0]
    cbnz    w1, .Lhave_sep
    add     x23, x23, #8
    sub     x24, x24, #1
    cbz     x24, .Lusage
    ldr     x0, [x23]
.Lhave_sep:
    str     x0, [x29, #L_SEP]
    bl      uolt_strlen
    str     x0, [x29, #L_SEPLEN]
    add     x23, x23, #8
    sub     x24, x24, #1
    b       .Lopt
.Lopt_ddash:
    ldrb    w1, [x0, #2]
    cbnz    w1, .Lusage
    add     x23, x23, #8
    sub     x24, x24, #1
.Lparsed:
    mov     x19, #1                     // first
    mov     x20, #1                     // incr
    cmp     x24, #1
    b.eq    .Lone
    cmp     x24, #2
    b.eq    .Ltwo
    cmp     x24, #3
    b.eq    .Lthree
    b       .Lusage
.Lone:
    ldr     x0, [x23]
    bl      parse_int
    cbnz    x1, .Lbad
    mov     x21, x0
    b       .Lready
.Ltwo:
    ldr     x0, [x23]
    bl      parse_int
    cbnz    x1, .Lbad
    mov     x19, x0
    ldr     x0, [x23, #8]
    bl      parse_int
    cbnz    x1, .Lbad
    mov     x21, x0
    b       .Lready
.Lthree:
    ldr     x0, [x23]
    bl      parse_int
    cbnz    x1, .Lbad
    mov     x19, x0
    ldr     x0, [x23, #8]
    bl      parse_int
    cbnz    x1, .Lbad
    mov     x20, x0
    ldr     x0, [x23, #16]
    bl      parse_int
    cbnz    x1, .Lbad
    mov     x21, x0
.Lready:
    cbz     x20, .Lbad                  // zero increment
    ldr     x9, [x29, #L_WIDTH]
    cbz     x9, .LnoW
    mov     x0, x19                     // width = max(fmt_len(first), fmt_len(last))
    bl      fmt_len
    mov     x23, x0
    mov     x0, x21
    bl      fmt_len
    cmp     x0, x23
    b.hs    1f
    mov     x0, x23
1:
    str     x0, [x29, #L_WIDTH]
.LnoW:
    mov     x22, x19                    // i = first
    mov     x9, #1
    str     x9, [x29, #L_FIRST]
.Lloop:
    cmp     x20, #0
    b.mi    .Ldown
    cmp     x22, x21                    // ascending: stop when i > last
    b.gt    .Ldone
    b       .Lemit
.Ldown:
    cmp     x22, x21                    // descending: stop when i < last
    b.lt    .Ldone
.Lemit:
    ldr     x9, [x29, #L_FIRST]
    cbnz    x9, .LnoSEP
    mov     x0, #STDOUT                 // separator before every number but the first
    ldr     x1, [x29, #L_SEP]
    ldr     x2, [x29, #L_SEPLEN]
    bl      uolt_write
.LnoSEP:
    str     xzr, [x29, #L_FIRST]
    mov     x0, x22
    bl      put_num
    add     x22, x22, x20
    b       .Lloop
.Ldone:
    ldr     x9, [x29, #L_FIRST]
    cmp     x9, #1
    b.eq    .Ldone0                     // empty sequence -> no trailing newline
    mov     w9, #0x0a
    add     x10, x29, #NLBYTE
    strb    w9, [x10]
    mov     x0, #STDOUT
    mov     x1, x10
    mov     x2, #1
    bl      uolt_write
.Ldone0:
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
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #160
    ret

// put_num(x0 = signed value): format zero-padded to L_WIDTH when set, no trailing
// newline, and write it. Backward-fills the buffer ending at x29+NUMEND. Makes no
// call before the tail branch, so lr stays valid for the return to uolt_main.
put_num:
    add     x1, x29, #NUMEND            // one past the buffer end (grows downward)
    mov     x3, #0                      // negative flag
    cmp     x0, #0
    b.ge    1f
    mov     x3, #1
    neg     x0, x0
1:
    mov     x6, #10
    mov     x5, #0                      // digit count
2:
    udiv    x9, x0, x6
    msub    x10, x9, x6, x0             // rem = x0 - (x0/10)*10
    add     w10, w10, #'0'
    sub     x1, x1, #1
    strb    w10, [x1]
    add     x5, x5, #1
    mov     x0, x9
    cbnz    x0, 2b
    ldr     x7, [x29, #L_WIDTH]         // pad with leading zeros to width
    cbz     x7, .Lpn_sign
    add     x4, x5, x3                  // current width = digits + sign
.Lpn_pad:
    cmp     x4, x7
    b.hs    .Lpn_sign
    sub     x1, x1, #1
    mov     w10, #'0'
    strb    w10, [x1]
    add     x4, x4, #1
    b       .Lpn_pad
.Lpn_sign:
    cbz     x3, 3f
    sub     x1, x1, #1
    mov     w10, #'-'
    strb    w10, [x1]
3:
    add     x2, x29, #NUMEND
    sub     x2, x2, x1                  // length
    mov     x0, #STDOUT
    b       uolt_write

// fmt_len(x0 = signed value) -> x0 = printed length (digits + sign).
fmt_len:
    mov     x8, #0                      // sign count
    cmp     x0, #0
    b.ge    1f
    mov     x8, #1
    neg     x0, x0
1:
    mov     x6, #10
    mov     x7, #0                      // digit count
2:
    udiv    x9, x0, x6
    mov     x0, x9
    add     x7, x7, #1
    cbnz    x0, 2b
    add     x0, x7, x8
    ret

// parse_int(x0 = ASCIZ) -> x0 = value, x1 = 0 ok / 1 error (empty or non-digit).
// Accepts an optional leading '-'. Makes no calls, so lr is untouched.
parse_int:
    mov     x2, x0                      // cursor
    mov     x0, #0                      // value
    mov     x3, #0                      // negative flag
    ldrb    w4, [x2]
    cmp     w4, #'-'
    b.ne    1f
    mov     x3, #1
    add     x2, x2, #1
1:
    mov     x5, #0                      // digit-seen flag
.Lpi:
    ldrb    w4, [x2]
    cbz     w4, .Lpi_done
    sub     w4, w4, #'0'
    cmp     w4, #9
    b.hi    .Lpi_err
    mov     x6, #10
    mul     x0, x0, x6
    add     x0, x0, w4, uxtw
    mov     x5, #1
    add     x2, x2, #1
    b       .Lpi
.Lpi_done:
    cbz     x5, .Lpi_err
    cbz     x3, 2f
    neg     x0, x0
2:
    mov     x1, #0
    ret
.Lpi_err:
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

nl:        .asciz "\n"
err_usage: .asciz "uolt-seq: usage: seq [-s STRING] [-w] [first [incr]] last\n"
err_bad:   .asciz "uolt-seq: invalid integer argument\n"
