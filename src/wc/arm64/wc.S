// src/wc/arm64/wc.S - uolt-wc: the POSIX `wc` utility (aarch64).
//
// Counts lines/words/bytes/chars of each operand (or stdin). Flags -l/-w/-c/-m
// select columns (combinable); default is lines/words/bytes. Columns always print
// in order lines, words, chars, bytes, then the name; a "total" line sums when
// >1 operand. C locale: a char is a byte, so -m == -c. One space between fields,
// no padding. No heap (Principle IV): 64 KB buffer + register/stack counters.
// Mirrors the x86_64 body (x86 `div` -> `udiv`/`msub`).
//
// Callee-saved roles: x19 = show mask (bit0 lines, bit1 words, bit2 bytes,
//   bit3 chars), x20 = buffer base, x21 = exit status, x22 = current operand/fd,
//   x23 = &argv walk. Locals off x29. count_fd returns x9=lines,x10=words,
//   x11=bytes (kernel-preserved across the read syscall).

#include "uolt.inc"

.set STDIN,    0
.set STDOUT,   1
.set STDERR,   2
.set O_RDONLY, 0
.set BUFSZ,    65536

.set LOC_L,     48
.set LOC_W,     56
.set LOC_C,     64
.set LOC_TL,    72
.set LOC_TW,    80
.set LOC_TC,    88
.set LOC_REM,   96
.set LOC_MULTI, 104
.set LOC_FF,    112
.set LOC_CH,    120
.set LOC_NUM,   128             // 20-byte decimal scratch

.text
.globl uolt_main
uolt_main:
    sub     sp, sp, #192
    mov     x29, sp
    stp     x19, x20, [sp, #0]
    stp     x21, x22, [sp, #16]
    stp     x23, x30, [sp, #32]
    sub     sp, sp, #BUFSZ
    mov     x20, sp
    mov     x21, #0

    // --- Option parsing: build the show mask, advance to operands. ---
    mov     x19, #0
    add     x23, x1, #8                 // &argv[1]
    sub     x9, x0, #1                  // operand count
.Lopt:
    cbz     x9, .Lopt_done
    ldr     x22, [x23]
    ldrb    w10, [x22]
    cmp     w10, #'-'
    b.ne    .Lopt_done
    ldrb    w10, [x22, #1]
    cbz     w10, .Lopt_done             // "-" -> operand
    cmp     w10, #'-'
    b.ne    .Lparse_flags
    ldrb    w10, [x22, #2]
    cbnz    w10, .Lparse_flags
    add     x23, x23, #8                // "--": end of options
    sub     x9, x9, #1
    b       .Lopt_done
.Lparse_flags:
    add     x11, x22, #1                // flags start
    mov     x12, x11
.Lval:
    ldrb    w10, [x12]
    cbz     w10, .Lapply
    cmp     w10, #'l'
    b.eq    1f
    cmp     w10, #'w'
    b.eq    1f
    cmp     w10, #'c'
    b.eq    1f
    cmp     w10, #'m'
    b.eq    1f
    b       .Lopt_done                  // unknown letter -> operand
1:
    add     x12, x12, #1
    b       .Lval
.Lapply:
    mov     x12, x11
.Lap:
    ldrb    w10, [x12]
    cbz     w10, .Lap_done
    cmp     w10, #'l'
    b.ne    2f
    orr     x19, x19, #1
2:
    cmp     w10, #'w'
    b.ne    3f
    orr     x19, x19, #2
3:
    cmp     w10, #'c'
    b.ne    5f
    orr     x19, x19, #4
5:
    cmp     w10, #'m'
    b.ne    4f
    orr     x19, x19, #8
4:
    add     x12, x12, #1
    b       .Lap
.Lap_done:
    add     x23, x23, #8
    sub     x9, x9, #1
    b       .Lopt

.Lopt_done:
    cbnz    x19, 1f
    mov     x19, #7                     // default: lines, words, bytes
1:
    str     x9, [x29, #LOC_REM]
    str     xzr, [x29, #LOC_TL]
    str     xzr, [x29, #LOC_TW]
    str     xzr, [x29, #LOC_TC]
    str     xzr, [x29, #LOC_MULTI]
    cmp     x9, #1
    b.ls    2f
    mov     x10, #1
    str     x10, [x29, #LOC_MULTI]
2:
    cbnz    x9, .Lhave

    mov     x22, #STDIN                 // no operand -> count stdin, no name
    bl      count_fd
    str     x9, [x29, #LOC_L]
    str     x10, [x29, #LOC_W]
    str     x11, [x29, #LOC_C]
    mov     x1, #0
    bl      emit_line
    b       .Lfinish

.Lhave:
.Lploop:
    ldr     x9, [x29, #LOC_REM]
    cbz     x9, .Ltotals
    ldr     x22, [x23]
    mov     x0, x22
    mov     x1, #O_RDONLY
    mov     x2, #0
    bl      uolt_open
    cmp     x0, #0
    b.mi    .Lwf_err
    mov     x22, x0                     // fd
    bl      count_fd                    // x9 lines, x10 words, x11 bytes
    mov     x0, x22
    bl      uolt_close                  // preserves x9/x10/x11
    str     x9, [x29, #LOC_L]
    str     x10, [x29, #LOC_W]
    str     x11, [x29, #LOC_C]
    ldr     x12, [x29, #LOC_TL]
    add     x12, x12, x9
    str     x12, [x29, #LOC_TL]
    ldr     x12, [x29, #LOC_TW]
    add     x12, x12, x10
    str     x12, [x29, #LOC_TW]
    ldr     x12, [x29, #LOC_TC]
    add     x12, x12, x11
    str     x12, [x29, #LOC_TC]
    ldr     x1, [x23]                   // name
    bl      emit_line
    b       .Lwnext
.Lwf_err:
    mov     x21, #1
    adr     x0, err_pre
    bl      err_puts
    ldr     x0, [x23]
    bl      err_puts
    adr     x0, err_suf
    bl      err_puts
.Lwnext:
    add     x23, x23, #8
    ldr     x9, [x29, #LOC_REM]
    sub     x9, x9, #1
    str     x9, [x29, #LOC_REM]
    b       .Lploop

.Ltotals:
    ldr     x9, [x29, #LOC_MULTI]
    cbz     x9, .Lfinish
    ldr     x9, [x29, #LOC_TL]
    str     x9, [x29, #LOC_L]
    ldr     x9, [x29, #LOC_TW]
    str     x9, [x29, #LOC_W]
    ldr     x9, [x29, #LOC_TC]
    str     x9, [x29, #LOC_C]
    adr     x1, total_name
    bl      emit_line

.Lfinish:
    mov     x0, x21
    add     sp, sp, #BUFSZ
    ldp     x19, x20, [sp, #0]
    ldp     x21, x22, [sp, #16]
    ldp     x23, x30, [sp, #32]
    add     sp, sp, #192
    ret

// count_fd(x22 = fd) -> x9 lines, x10 words, x11 bytes; sets x21 on read error.
// x12 = in-word flag. Counts survive the read syscall (kernel-preserved).
count_fd:
    stp     x29, x30, [sp, #-16]!
    mov     x9, #0                      // lines
    mov     x10, #0                     // words
    mov     x11, #0                     // bytes
    mov     x12, #0                     // in-word flag
.Lcf_read:
    mov     x0, x22
    mov     x1, x20
    mov     x2, #BUFSZ
    bl      uolt_read
    cmp     x0, #0
    b.eq    .Lcf_done
    b.mi    .Lcf_err
    add     x11, x11, x0                // bytes += got
    mov     x13, #0                     // i
.Lcf_scan:
    cmp     x13, x0
    b.hs    .Lcf_read
    ldrb    w14, [x20, x13]
    cmp     w14, #0x0a                  // newline -> a line
    b.ne    1f
    add     x9, x9, #1
1:
    cmp     w14, #0x20                  // <blank>? space ...
    b.eq    .Lcf_ws
    sub     w15, w14, #9                // ... or 0x09..0x0d
    cmp     w15, #4
    b.ls    .Lcf_ws
    cbnz    x12, 2f                     // non-blank: start of a word?
    add     x10, x10, #1
    mov     x12, #1
2:
    add     x13, x13, #1
    b       .Lcf_scan
.Lcf_ws:
    mov     x12, #0                     // blank ends the current word
    add     x13, x13, #1
    b       .Lcf_scan
.Lcf_err:
    mov     x21, #1
.Lcf_done:
    ldp     x29, x30, [sp], #16
    ret

// emit_line(x1 = name, or 0): print the enabled counts then " name" and newline.
emit_line:
    stp     x29, x30, [sp, #-16]!
    mov     x3, x1                      // name (survives put_* calls)
    mov     x9, #1
    str     x9, [x29, #LOC_FF]
    tst     x19, #1
    b.eq    1f
    bl      sep_if_needed
    ldr     x0, [x29, #LOC_L]
    bl      put_uint
1:
    tst     x19, #2
    b.eq    2f
    bl      sep_if_needed
    ldr     x0, [x29, #LOC_W]
    bl      put_uint
2:
    tst     x19, #8                     // -m characters (before bytes, GNU order)
    b.eq    5f
    bl      sep_if_needed
    ldr     x0, [x29, #LOC_C]
    bl      put_uint
5:
    tst     x19, #4
    b.eq    3f
    bl      sep_if_needed
    ldr     x0, [x29, #LOC_C]
    bl      put_uint
3:
    cbz     x3, 4f
    mov     w0, #' '
    bl      put_char
    mov     x1, x3
    bl      put_str
4:
    mov     w0, #0x0a
    bl      put_char
    ldp     x29, x30, [sp], #16
    ret

// sep_if_needed: emit a single space before every field except the first.
sep_if_needed:
    ldr     x9, [x29, #LOC_FF]
    cbz     x9, 1f
    str     xzr, [x29, #LOC_FF]
    ret
1:
    mov     w0, #' '
    // fall through to put_char (tail)

// put_char(w0 = byte): write one byte to stdout.
put_char:
    strb    w0, [x29, #LOC_CH]
    mov     x0, #STDOUT
    add     x1, x29, #LOC_CH
    mov     x2, #1
    b       uolt_write

// put_str(x1 = ASCIZ): write the string to stdout. Saves lr (calls strlen).
put_str:
    stp     x29, x30, [sp, #-16]!
    mov     x3, x1
    mov     x0, x1
    bl      uolt_strlen
    mov     x2, x0
    mov     x1, x3
    mov     x0, #STDOUT
    bl      uolt_write
    ldp     x29, x30, [sp], #16
    ret

// put_uint(x0 = value): write the unsigned decimal value to stdout. Saves lr.
put_uint:
    stp     x29, x30, [sp, #-16]!
    add     x1, x29, #LOC_NUM
    add     x1, x1, #20                 // one past the scratch end
    cbnz    x0, 1f
    sub     x1, x1, #1                  // value 0 -> "0"
    mov     w2, #'0'
    strb    w2, [x1]
    b       2f
1:
    mov     x9, x0                      // working value
    mov     x10, #10
.Lpu_loop:
    cbz     x9, 2f
    udiv    x11, x9, x10
    msub    x2, x11, x10, x9            // digit = value - (value/10)*10
    add     w2, w2, #'0'
    sub     x1, x1, #1
    strb    w2, [x1]
    mov     x9, x11
    b       .Lpu_loop
2:
    add     x9, x29, #LOC_NUM
    add     x9, x9, #20
    sub     x2, x9, x1                  // length
    mov     x0, #STDOUT
    bl      uolt_write
    ldp     x29, x30, [sp], #16
    ret

// err_puts(x0 = ASCIZ) -> stderr; length via strlen. Saves lr.
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

total_name: .asciz  "total"
err_pre:    .asciz  "uolt-wc: "
err_suf:    .asciz  ": cannot open\n"
