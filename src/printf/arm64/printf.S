// src/printf/arm64/printf.S - uolt-printf: the POSIX `printf` utility, aarch64.
//
// printf format [argument...]: write the arguments under the control of the
// format string, cycling the format as long as unconsumed arguments remain and
// the previous pass consumed at least one argument. Mirrors the x86_64 body.
//
// Supported: backslash escapes \\ \a \b \f \n \r \t \v \" and \ddd; conversions
// %d %i %u %o %x %X %c %s %b %%; flags - + (space) # 0; decimal field width and
// precision (each capped at WIDTHMAX). Floating conversions and dynamic '*' are
// deferred. Numeric args parse like C integer constants; a leading ' or " takes
// the next byte's value (POSIX). Missing args are "" for %s/%c, 0 for numerics.
//
// All output funnels through one 4 KB buffer (OBUF); helpers keep live state in
// stack locals so the callee-saved format-walk registers survive every call. No
// heap (Principle IV): buffers and the number scratch live in the stack frame.
//
// Callee-saved: x19 = format base, x20 = format walk ptr, x21 = consumed-before
//   mark. conv_num keeps dptr=x22, plen=x23, dlen=x24 (saved by conv_num).

#include "uolt.inc"

.set STDOUT, 1
.set STDERR, 2

.set FLAG_MINUS, 1              // '-' bit0
.set FLAG_PLUS,  2             // '+' bit1
.set FLAG_SPACE, 4            // ' ' bit2
.set FLAG_HASH,  8            // '#' bit3
.set FLAG_ZERO,  16           // '0' bit4

.set WIDTHMAX, 256
.set OBSIZE,   4096
.set BSIZE,    4096

// Stack locals (off x29). Saved x19/x20/x21/x30 occupy [0..31].
.set LOC_ARGP,     32
.set LOC_ARGC,     40
.set LOC_ARGI,     48
.set LOC_WIDTH,    56
.set LOC_PREC,     64
.set LOC_PPTR,     72
.set LOC_PLEN,     80
.set LOC_PADN2,    88
.set LOC_SPTR,     96
.set LOC_SLEN,     104
.set LOC_ESPAD,    112
.set LOC_CNPAD,    120
.set LOC_FLAGS,    128
.set LOC_UPPER,    136
.set LOC_UNSIGNED, 144
.set LOC_NEG,      152
.set LOC_NONZERO,  160
.set LOC_BASE,     168
.set LOC_PADCH,    176
.set OBLEN,        184
.set PFXOFF,       192          // 8-byte sign/hex-prefix scratch
.set NUMEND,       520          // number buffer built downward from here [200,520)
.set OBOFF,        520          // output buffer [520, 4616)
.set BBUFOFF,      4616          // %b expansion buffer [4616, 8712)
.set FRAME,        8720

.text
.globl uolt_main
uolt_main:
    sub     sp, sp, #8192
    sub     sp, sp, #528
    mov     x29, sp
    stp     x19, x20, [sp, #0]
    stp     x21, x30, [sp, #16]

    cmp     x0, #2
    b.lt    .missing_format
    add     x9, x1, #16                // &argv[2]
    str     x9, [x29, #LOC_ARGP]
    sub     x9, x0, #2                 // argument count
    str     x9, [x29, #LOC_ARGC]
    ldr     x19, [x1, #8]              // format = argv[1]
    str     xzr, [x29, #LOC_ARGI]
    str     xzr, [x29, #OBLEN]

.cycle:
    ldr     x21, [x29, #LOC_ARGI]      // consumed-before mark for this pass
    mov     x20, x19                   // format walk pointer
.fmt_loop:
    ldrb    w9, [x20]
    cbz     w9, .fmt_end
    cmp     w9, #0x5c                  // '\'
    b.eq    .esc
    cmp     w9, #'%'
    b.eq    .conv
    mov     w0, w9                     // ordinary byte
    bl      ob_putc
    add     x20, x20, #1
    b       .fmt_loop
.esc:
    add     x20, x20, #1               // past '\'
    bl      do_escape
    b       .fmt_loop
.conv:
    add     x20, x20, #1               // past '%'
    ldrb    w9, [x20]
    cmp     w9, #'%'
    b.ne    .conv_spec
    add     x20, x20, #1
    mov     w0, #'%'
    bl      ob_putc
    b       .fmt_loop
.fmt_end:
    ldr     x9, [x29, #LOC_ARGI]
    ldr     x10, [x29, #LOC_ARGC]
    cmp     x9, x10
    b.hs    .finish
    cmp     x9, x21
    b.ls    .finish
    b       .cycle
.finish:
    bl      ob_flush
    mov     x0, #0
    b       .ret
.missing_format:
    adr     x0, err_usage
    bl      err_puts
    mov     x0, #1
    b       .ret
.bad_spec:
    bl      ob_flush
    adr     x0, err_spec
    bl      err_puts
    mov     x0, #1
.ret:
    ldp     x19, x20, [sp, #0]
    ldp     x21, x30, [sp, #16]
    add     sp, sp, #8192
    add     sp, sp, #528
    ret

// -------- conversion specification: flags, width, precision, conversion -------
.conv_spec:
    str     xzr, [x29, #LOC_FLAGS]
    str     xzr, [x29, #LOC_WIDTH]
    mov     x9, #-1
    str     x9, [x29, #LOC_PREC]
    str     xzr, [x29, #LOC_UPPER]
    str     xzr, [x29, #LOC_UNSIGNED]
    str     xzr, [x29, #LOC_NEG]
.cs_flags:
    ldrb    w9, [x20]
    cmp     w9, #'-'
    b.eq    .fl_minus
    cmp     w9, #'+'
    b.eq    .fl_plus
    cmp     w9, #' '
    b.eq    .fl_space
    cmp     w9, #'#'
    b.eq    .fl_hash
    cmp     w9, #'0'
    b.eq    .fl_zero
    b       .cs_width
.fl_minus:
    ldr     x9, [x29, #LOC_FLAGS]
    orr     x9, x9, #FLAG_MINUS
    str     x9, [x29, #LOC_FLAGS]
    add     x20, x20, #1
    b       .cs_flags
.fl_plus:
    ldr     x9, [x29, #LOC_FLAGS]
    orr     x9, x9, #FLAG_PLUS
    str     x9, [x29, #LOC_FLAGS]
    add     x20, x20, #1
    b       .cs_flags
.fl_space:
    ldr     x9, [x29, #LOC_FLAGS]
    orr     x9, x9, #FLAG_SPACE
    str     x9, [x29, #LOC_FLAGS]
    add     x20, x20, #1
    b       .cs_flags
.fl_hash:
    ldr     x9, [x29, #LOC_FLAGS]
    orr     x9, x9, #FLAG_HASH
    str     x9, [x29, #LOC_FLAGS]
    add     x20, x20, #1
    b       .cs_flags
.fl_zero:
    ldr     x9, [x29, #LOC_FLAGS]
    orr     x9, x9, #FLAG_ZERO
    str     x9, [x29, #LOC_FLAGS]
    add     x20, x20, #1
    b       .cs_flags

.cs_width:
    mov     w9, #0
.csw_l:
    ldrb    w10, [x20]
    sub     w10, w10, #'0'
    cmp     w10, #9
    b.hi    .csw_done
    mov     w11, #10
    mul     w9, w9, w11
    add     w9, w9, w10
    add     x20, x20, #1
    b       .csw_l
.csw_done:
    cmp     w9, #WIDTHMAX
    b.ls    .csw_store
    mov     w9, #WIDTHMAX
.csw_store:
    str     x9, [x29, #LOC_WIDTH]

.cs_prec:
    ldrb    w9, [x20]
    cmp     w9, #'.'
    b.ne    .cs_conv
    add     x20, x20, #1
    mov     w9, #0                     // precision defaults to 0 when '.' given
.csp_l:
    ldrb    w10, [x20]
    sub     w10, w10, #'0'
    cmp     w10, #9
    b.hi    .csp_done
    mov     w11, #10
    mul     w9, w9, w11
    add     w9, w9, w10
    add     x20, x20, #1
    b       .csp_l
.csp_done:
    cmp     w9, #WIDTHMAX
    b.ls    .csp_store
    mov     w9, #WIDTHMAX
.csp_store:
    str     x9, [x29, #LOC_PREC]

.cs_conv:
    ldrb    w9, [x20]
    cbz     w9, .bad_spec
    add     x20, x20, #1
    cmp     w9, #'d'
    b.eq    .c_int_s
    cmp     w9, #'i'
    b.eq    .c_int_s
    cmp     w9, #'u'
    b.eq    .c_u
    cmp     w9, #'o'
    b.eq    .c_o
    cmp     w9, #'x'
    b.eq    .c_x
    cmp     w9, #'X'
    b.eq    .c_X
    cmp     w9, #'c'
    b.eq    .c_c
    cmp     w9, #'s'
    b.eq    .c_s
    cmp     w9, #'b'
    b.eq    .c_b
    b       .bad_spec

.c_int_s:
    mov     w9, #10
    str     x9, [x29, #LOC_BASE]
    bl      next_arg
    bl      parse_num                  // x0 = signed value
    tst     x0, x0
    b.pl    .cis_pos
    mov     x9, #1
    str     x9, [x29, #LOC_NEG]
    neg     x0, x0
.cis_pos:
    str     xzr, [x29, #LOC_NONZERO]
    cbz     x0, .cis_go
    mov     x9, #1
    str     x9, [x29, #LOC_NONZERO]
.cis_go:
    bl      conv_num
    b       .fmt_loop

.c_u:
    mov     w9, #10
    str     x9, [x29, #LOC_BASE]
    mov     x9, #1
    str     x9, [x29, #LOC_UNSIGNED]
    b       .num_unsigned
.c_o:
    mov     w9, #8
    str     x9, [x29, #LOC_BASE]
    mov     x9, #1
    str     x9, [x29, #LOC_UNSIGNED]
    b       .num_unsigned
.c_x:
    mov     w9, #16
    str     x9, [x29, #LOC_BASE]
    mov     x9, #1
    str     x9, [x29, #LOC_UNSIGNED]
    b       .num_unsigned
.c_X:
    mov     w9, #16
    str     x9, [x29, #LOC_BASE]
    mov     x9, #1
    str     x9, [x29, #LOC_UPPER]
    mov     x9, #1
    str     x9, [x29, #LOC_UNSIGNED]
.num_unsigned:
    bl      next_arg
    bl      parse_num                  // treat the bit pattern as unsigned
    str     xzr, [x29, #LOC_NONZERO]
    cbz     x0, .nu_go
    mov     x9, #1
    str     x9, [x29, #LOC_NONZERO]
.nu_go:
    bl      conv_num
    b       .fmt_loop

.c_c:
    bl      next_arg
    mov     x1, x0
    ldrb    w9, [x1]
    cbnz    w9, .cc_one
    mov     x2, #0                     // empty argument: width padding only
    b       .cc_emit
.cc_one:
    mov     x2, #1
.cc_emit:
    bl      emit_str
    b       .fmt_loop

.c_s:
    bl      next_arg
    str     x0, [x29, #LOC_SPTR]       // stash ptr across strlen
    bl      uolt_strlen                // x0 = length
    mov     x2, x0
    ldr     x1, [x29, #LOC_SPTR]
    ldr     x9, [x29, #LOC_PREC]
    tbnz    x9, #63, .cs_emit          // no precision
    cmp     x2, x9
    b.ls    .cs_emit
    mov     x2, x9                     // truncate to precision
.cs_emit:
    bl      emit_str
    b       .fmt_loop

// %b: copy the argument translating backslash escapes into BBUF (bounded), then
// emit like %s. "\c" stops all further output immediately. x1=src, x2=dst, x3=len.
.c_b:
    bl      next_arg
    mov     x1, x0                     // src
    mov     x2, #BBUFOFF
    add     x2, x29, x2                // dst
    mov     x3, #0                     // produced length
.cb_l:
    cmp     x3, #BSIZE
    b.hs    .cb_done
    ldrb    w9, [x1]
    cbz     w9, .cb_done
    cmp     w9, #0x5c                  // '\'
    b.ne    .cb_plain
    add     x1, x1, #1
    ldrb    w9, [x1]
    cbz     w9, .cb_lonebs             // trailing backslash
    cmp     w9, #'c'
    b.eq    .cb_stop
    sub     w10, w9, #'0'              // octal escape?
    cmp     w10, #7
    b.ls    .cb_oct
    mov     w0, w9
    bl      named_esc                  // x0 = byte, or -1 if unknown
    cmp     x0, #0
    b.mi    .cb_unknown
    strb    w0, [x2]
    add     x2, x2, #1
    add     x3, x3, #1
    add     x1, x1, #1
    b       .cb_l
.cb_unknown:
    mov     w0, #0x5c                  // keep the backslash, then the byte (w9)
    strb    w0, [x2]
    add     x2, x2, #1
    add     x3, x3, #1
    cmp     x3, #BSIZE
    b.hs    .cb_done
    strb    w9, [x2]
    add     x2, x2, #1
    add     x3, x3, #1
    add     x1, x1, #1
    b       .cb_l
.cb_lonebs:
    mov     w0, #0x5c
    strb    w0, [x2]
    add     x2, x2, #1
    add     x3, x3, #1
    b       .cb_done
.cb_oct:
    mov     w0, #0                     // value
    mov     w10, #0                    // digit count
.cbo_l:
    ldrb    w11, [x1]
    sub     w11, w11, #'0'
    cmp     w11, #7
    b.hi    .cbo_done
    lsl     w0, w0, #3
    add     w0, w0, w11
    add     x1, x1, #1
    add     w10, w10, #1
    cmp     w10, #3
    b.lo    .cbo_l
.cbo_done:
    strb    w0, [x2]
    add     x2, x2, #1
    add     x3, x3, #1
    b       .cb_l
.cb_plain:
    strb    w9, [x2]
    add     x2, x2, #1
    add     x3, x3, #1
    add     x1, x1, #1
    b       .cb_l
.cb_done:
    mov     x1, #BBUFOFF
    add     x1, x29, x1
    mov     x2, x3
    ldr     x9, [x29, #LOC_PREC]
    tbnz    x9, #63, .cb_emit
    cmp     x2, x9
    b.ls    .cb_emit
    mov     x2, x9
.cb_emit:
    bl      emit_str
    b       .fmt_loop
.cb_stop:
    mov     x1, #BBUFOFF
    add     x1, x29, x1
    mov     x2, x3
    bl      emit_str
    bl      ob_flush
    mov     x0, #0
    b       .ret

// ---------------------------- helper routines --------------------------------

// next_arg() -> x0 = pointer to the next ASCIZ argument, advancing the index.
// When exhausted, returns "" and does NOT advance. Leaf.
next_arg:
    ldr     x0, [x29, #LOC_ARGI]
    ldr     x9, [x29, #LOC_ARGC]
    cmp     x0, x9
    b.hs    .na_empty
    ldr     x9, [x29, #LOC_ARGP]
    ldr     x0, [x9, x0, lsl #3]
    ldr     x10, [x29, #LOC_ARGI]
    add     x10, x10, #1
    str     x10, [x29, #LOC_ARGI]
    ret
.na_empty:
    adr     x0, empty
    ret

// do_escape(): translate the escape at [x20], emit it, advance x20. An
// unrecognized escape prints '\' and leaves the byte for the normal path.
do_escape:
    stp     x29, x30, [sp, #-16]!
    ldrb    w9, [x20]
    sub     w10, w9, #'0'
    cmp     w10, #7
    b.ls    .de_oct
    mov     w0, w9
    bl      named_esc
    cmp     x0, #0
    b.mi    .de_unknown
    add     x20, x20, #1
    ldp     x29, x30, [sp], #16
    b       ob_putc
.de_unknown:
    mov     w0, #0x5c                  // leave [x20] to be printed next
    ldp     x29, x30, [sp], #16
    b       ob_putc
.de_oct:
    mov     w0, #0
    mov     w10, #0
.deo_l:
    ldrb    w11, [x20]
    sub     w11, w11, #'0'
    cmp     w11, #7
    b.hi    .deo_done
    lsl     w0, w0, #3
    add     w0, w0, w11
    add     x20, x20, #1
    add     w10, w10, #1
    cmp     w10, #3
    b.lo    .deo_l
.deo_done:
    ldp     x29, x30, [sp], #16
    b       ob_putc

// named_esc(w0 = char) -> x0 = translated byte, or x0 = -1 if not a named escape.
// Leaf; clobbers only x0.
named_esc:
    cmp     w0, #0x5c
    b.eq    .ne_bs
    cmp     w0, #'a'
    b.eq    .ne_a
    cmp     w0, #'b'
    b.eq    .ne_b
    cmp     w0, #'f'
    b.eq    .ne_f
    cmp     w0, #'n'
    b.eq    .ne_n
    cmp     w0, #'r'
    b.eq    .ne_r
    cmp     w0, #'t'
    b.eq    .ne_t
    cmp     w0, #'v'
    b.eq    .ne_v
    cmp     w0, #'"'
    b.eq    .ne_dq
    mov     x0, #-1
    ret
.ne_bs:
    mov     x0, #0x5c
    ret
.ne_a:
    mov     x0, #7
    ret
.ne_b:
    mov     x0, #8
    ret
.ne_f:
    mov     x0, #12
    ret
.ne_n:
    mov     x0, #10
    ret
.ne_r:
    mov     x0, #13
    ret
.ne_t:
    mov     x0, #9
    ret
.ne_v:
    mov     x0, #11
    ret
.ne_dq:
    mov     x0, #'"'
    ret

// parse_num(x0 = ASCIZ) -> x0 = value. Leaf.
parse_num:
    mov     x1, x0                     // cursor
    mov     x8, #0                     // sign
    mov     x0, #0                     // value
.pn_skip:
    ldrb    w2, [x1]
    cmp     w2, #' '
    b.eq    .pn_adv
    cmp     w2, #9
    b.ne    .pn_lead
.pn_adv:
    add     x1, x1, #1
    b       .pn_skip
.pn_lead:
    cmp     w2, #0x27                  // '
    b.eq    .pn_char
    cmp     w2, #0x22                  // "
    b.eq    .pn_char
    cmp     w2, #'-'
    b.ne    .pn_plus
    mov     x8, #1
    add     x1, x1, #1
    b       .pn_radix
.pn_plus:
    cmp     w2, #'+'
    b.ne    .pn_radix
    add     x1, x1, #1
.pn_radix:
    ldrb    w2, [x1]
    cmp     w2, #'0'
    b.ne    .pn_dec
    ldrb    w3, [x1, #1]
    orr     w3, w3, #0x20
    cmp     w3, #'x'
    b.eq    .pn_hex
    b       .pn_oct
.pn_char:
    ldrb    w0, [x1, #1]
    ret
.pn_dec:
    mov     x0, #0
.pnd_l:
    ldrb    w2, [x1]
    sub     w2, w2, #'0'
    cmp     w2, #9
    b.hi    .pn_fin
    mov     x3, #10
    mul     x0, x0, x3
    add     x0, x0, w2, uxtw
    add     x1, x1, #1
    b       .pnd_l
.pn_oct:
    add     x1, x1, #1                 // skip the leading 0
    mov     x0, #0
.pno_l:
    ldrb    w2, [x1]
    sub     w2, w2, #'0'
    cmp     w2, #7
    b.hi    .pn_fin
    lsl     x0, x0, #3
    add     x0, x0, w2, uxtw
    add     x1, x1, #1
    b       .pno_l
.pn_hex:
    add     x1, x1, #2                 // skip 0x
    mov     x0, #0
.pnh_l:
    ldrb    w2, [x1]
    cmp     w2, #'0'
    b.lo    .pn_fin
    cmp     w2, #'9'
    b.ls    .pnh_dig
    orr     w2, w2, #0x20
    cmp     w2, #'a'
    b.lo    .pn_fin
    cmp     w2, #'f'
    b.hi    .pn_fin
    sub     w2, w2, #('a' - 10)
    b       .pnh_add
.pnh_dig:
    sub     w2, w2, #'0'
.pnh_add:
    lsl     x0, x0, #4
    add     x0, x0, w2, uxtw
    add     x1, x1, #1
    b       .pnh_l
.pn_fin:
    cbz     x8, .pn_ret
    neg     x0, x0
.pn_ret:
    ret

// conv_num(x0 = magnitude, unsigned): format per LOC_BASE / LOC_* and emit.
// dptr=x22, plen=x23, dlen=x24 stay live across the emit helpers (saved here).
conv_num:
    sub     sp, sp, #32
    stp     x22, x23, [sp, #0]
    stp     x24, x30, [sp, #16]
    mov     x22, #NUMEND
    add     x22, x29, x22              // build digits downward from NUMEND
    ldrb    w11, [x29, #LOC_BASE]
    cbnz    x0, .cn_digits
    ldr     x9, [x29, #LOC_PREC]
    cmp     x9, #0
    b.eq    .cn_precdone               // value 0, precision 0 -> no digits
    sub     x22, x22, #1
    mov     w9, #'0'
    strb    w9, [x22]
    b       .cn_precdone
.cn_digits:
    udiv    x9, x0, x11
    msub    x10, x9, x11, x0           // rem = x0 - (x0/base)*base
    cmp     x10, #9
    b.hi    .cn_dighex
    add     w10, w10, #'0'
    b       .cn_digput
.cn_dighex:
    sub     w10, w10, #10
    add     w10, w10, #'a'
    ldrb    w12, [x29, #LOC_UPPER]
    cbz     w12, .cn_digput
    sub     w10, w10, #0x20           // 'a'..'f' -> 'A'..'F'
.cn_digput:
    sub     x22, x22, #1
    strb    w10, [x22]
    mov     x0, x9
    cbnz    x0, .cn_digits
.cn_precdone:
    ldr     x0, [x29, #LOC_PREC]       // pad the digit field to precision
    cmp     x0, #0
    b.mi    .cn_octhash
    mov     x9, #NUMEND
    add     x9, x29, x9
    sub     x9, x9, x22                // current digit count
.cn_pz:
    cmp     x9, x0
    b.hs    .cn_octhash
    sub     x22, x22, #1
    mov     w10, #'0'
    strb    w10, [x22]
    add     x9, x9, #1
    b       .cn_pz
.cn_octhash:
    ldr     x9, [x29, #LOC_FLAGS]      // '#': octal gets a guaranteed leading 0
    tbz     x9, #3, .cn_prefix
    ldrb    w9, [x29, #LOC_BASE]
    cmp     w9, #8
    b.ne    .cn_prefix
    ldrb    w9, [x22]
    cmp     w9, #'0'
    b.eq    .cn_prefix
    sub     x22, x22, #1
    mov     w9, #'0'
    strb    w9, [x22]
.cn_prefix:
    mov     x23, #0                    // plen
    ldrb    w9, [x29, #LOC_UNSIGNED]
    cbnz    w9, .cn_hexhash
    ldrb    w9, [x29, #LOC_NEG]
    cbz     w9, .cn_possign
    add     x10, x29, #PFXOFF
    mov     w9, #'-'
    strb    w9, [x10, x23]
    add     x23, x23, #1
    b       .cn_hexhash
.cn_possign:
    ldr     x9, [x29, #LOC_FLAGS]
    tbz     x9, #1, .cn_spaceflag      // FLAG_PLUS
    add     x10, x29, #PFXOFF
    mov     w9, #'+'
    strb    w9, [x10, x23]
    add     x23, x23, #1
    b       .cn_hexhash
.cn_spaceflag:
    ldr     x9, [x29, #LOC_FLAGS]
    tbz     x9, #2, .cn_hexhash        // FLAG_SPACE
    add     x10, x29, #PFXOFF
    mov     w9, #' '
    strb    w9, [x10, x23]
    add     x23, x23, #1
.cn_hexhash:
    ldr     x9, [x29, #LOC_FLAGS]
    tbz     x9, #3, .cn_measure        // FLAG_HASH
    ldrb    w9, [x29, #LOC_BASE]
    cmp     w9, #16
    b.ne    .cn_measure
    ldrb    w9, [x29, #LOC_NONZERO]
    cbz     w9, .cn_measure
    add     x10, x29, #PFXOFF
    mov     w9, #'0'
    strb    w9, [x10, x23]
    add     x23, x23, #1
    mov     w9, #'x'
    ldrb    w12, [x29, #LOC_UPPER]
    cbz     w12, .cn_hh_put
    mov     w9, #'X'
.cn_hh_put:
    add     x10, x29, #PFXOFF
    strb    w9, [x10, x23]
    add     x23, x23, #1
.cn_measure:
    mov     x9, #NUMEND
    add     x9, x29, x9
    sub     x24, x9, x22               // dlen
    add     x9, x23, x24               // core length = plen + dlen
    ldr     x10, [x29, #LOC_WIDTH]
    sub     x10, x10, x9               // pad = width - core
    cmp     x10, #0
    b.le    .cn_plain
    str     x10, [x29, #LOC_CNPAD]
    ldr     x9, [x29, #LOC_FLAGS]
    tbnz    x9, #0, .cn_left           // FLAG_MINUS
    tbz     x9, #4, .cn_spaceright     // FLAG_ZERO
    ldr     x9, [x29, #LOC_PREC]
    cmp     x9, #0
    b.ge    .cn_spaceright             // precision disables 0-pad for integers
    // zero pad: prefix, then zeros, then digits
    add     x1, x29, #PFXOFF
    mov     x2, x23
    bl      ob_put
    ldr     x0, [x29, #LOC_CNPAD]
    mov     w1, #'0'
    bl      emit_pad
    mov     x1, x22
    mov     x2, x24
    bl      ob_put
    b       .cn_ret
.cn_spaceright:
    ldr     x0, [x29, #LOC_CNPAD]
    mov     w1, #' '
    bl      emit_pad
    add     x1, x29, #PFXOFF
    mov     x2, x23
    bl      ob_put
    mov     x1, x22
    mov     x2, x24
    bl      ob_put
    b       .cn_ret
.cn_left:
    add     x1, x29, #PFXOFF
    mov     x2, x23
    bl      ob_put
    mov     x1, x22
    mov     x2, x24
    bl      ob_put
    ldr     x0, [x29, #LOC_CNPAD]
    mov     w1, #' '
    bl      emit_pad
    b       .cn_ret
.cn_plain:
    add     x1, x29, #PFXOFF
    mov     x2, x23
    bl      ob_put
    mov     x1, x22
    mov     x2, x24
    bl      ob_put
.cn_ret:
    ldp     x22, x23, [sp, #0]
    ldp     x24, x30, [sp, #16]
    add     sp, sp, #32
    ret

// emit_str(x1 = ptr, x2 = len): write padded to LOC_WIDTH with spaces, honoring
// FLAG_MINUS. Precision is applied by the caller.
emit_str:
    stp     x29, x30, [sp, #-16]!
    str     x1, [x29, #LOC_SPTR]
    str     x2, [x29, #LOC_SLEN]
    ldr     x9, [x29, #LOC_WIDTH]
    sub     x9, x9, x2
    cmp     x9, #0
    b.le    .es_plain
    str     x9, [x29, #LOC_ESPAD]
    ldr     x10, [x29, #LOC_FLAGS]
    tbnz    x10, #0, .es_left          // FLAG_MINUS
    ldr     x0, [x29, #LOC_ESPAD]
    mov     w1, #' '
    bl      emit_pad
    ldr     x1, [x29, #LOC_SPTR]
    ldr     x2, [x29, #LOC_SLEN]
    bl      ob_put
    b       .es_ret
.es_left:
    ldr     x1, [x29, #LOC_SPTR]
    ldr     x2, [x29, #LOC_SLEN]
    bl      ob_put
    ldr     x0, [x29, #LOC_ESPAD]
    mov     w1, #' '
    bl      emit_pad
    b       .es_ret
.es_plain:
    ldr     x1, [x29, #LOC_SPTR]
    ldr     x2, [x29, #LOC_SLEN]
    bl      ob_put
.es_ret:
    ldp     x29, x30, [sp], #16
    ret

// emit_pad(x0 = count, w1 = fill byte): emit the fill byte count times.
emit_pad:
    stp     x29, x30, [sp, #-16]!
    str     x0, [x29, #LOC_PADN2]
    strb    w1, [x29, #LOC_PADCH]
.ep_l:
    ldr     x9, [x29, #LOC_PADN2]
    cmp     x9, #0
    b.le    .ep_ret
    ldrb    w0, [x29, #LOC_PADCH]
    bl      ob_putc
    ldr     x9, [x29, #LOC_PADN2]
    sub     x9, x9, #1
    str     x9, [x29, #LOC_PADN2]
    b       .ep_l
.ep_ret:
    ldp     x29, x30, [sp], #16
    ret

// ---------------------- buffered output (OBUF) -------------------------------

// ob_putc(w0 = byte): append one byte to OBUF, flushing first if full. The byte
// is stacked across the flush so a full buffer stays correct.
ob_putc:
    ldr     x9, [x29, #OBLEN]
    cmp     x9, #OBSIZE
    b.lo    .opc_store
    stp     x0, x30, [sp, #-16]!
    bl      ob_flush
    ldp     x0, x30, [sp], #16
.opc_store:
    ldr     x9, [x29, #OBLEN]
    add     x10, x29, #OBOFF
    strb    w0, [x10, x9]
    add     x9, x9, #1
    str     x9, [x29, #OBLEN]
    ret

// ob_put(x1 = ptr, x2 = len): append len bytes (OBUF batches the syscalls).
ob_put:
    stp     x29, x30, [sp, #-16]!
    str     x1, [x29, #LOC_PPTR]
    str     x2, [x29, #LOC_PLEN]
.obp_l:
    ldr     x9, [x29, #LOC_PLEN]
    cmp     x9, #0
    b.le    .obp_ret
    ldr     x10, [x29, #LOC_PPTR]
    ldrb    w0, [x10]
    bl      ob_putc
    ldr     x10, [x29, #LOC_PPTR]
    add     x10, x10, #1
    str     x10, [x29, #LOC_PPTR]
    ldr     x9, [x29, #LOC_PLEN]
    sub     x9, x9, #1
    str     x9, [x29, #LOC_PLEN]
    b       .obp_l
.obp_ret:
    ldp     x29, x30, [sp], #16
    ret

// ob_flush(): write OBUF to stdout and reset it.
ob_flush:
    ldr     x2, [x29, #OBLEN]
    cbz     x2, .obf_ret
    stp     x29, x30, [sp, #-16]!
    mov     x0, #STDOUT
    add     x1, x29, #OBOFF
    bl      uolt_write
    str     xzr, [x29, #OBLEN]
    ldp     x29, x30, [sp], #16
.obf_ret:
    ret

// err_puts(x0 = ASCIZ): write a diagnostic to stderr.
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

empty:      .asciz ""
err_usage:  .asciz "uolt-printf: usage: printf format [argument...]\n"
err_spec:   .asciz "uolt-printf: invalid conversion specification\n"
