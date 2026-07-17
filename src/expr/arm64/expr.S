// src/expr/arm64/expr.S - uolt-expr: the POSIX `expr` utility, aarch64.
//
// expr EXPRESSION: evaluate an expression and write its value. Exit 0 if the
// value is neither null nor "0", 1 if it is, 2 on an invalid expression or a
// runtime error (non-integer operand, division by zero). Mirrors the x86_64 body.
//
// Operators, lowest precedence first (each its own argv token, left-associative):
//   |  &  (< <= = != >= >)  (+ -)  (* / %)  ( expr )
// The `:` BRE match operator is deferred. Overflow is not detected (64-bit wrap).
// No heap (Principle IV): results are formatted into a fixed stack arena. x86 idiv
// becomes aarch64 sdiv/msub.
//
// x19 = operand base (&argv[1]), x20 = operand count, held across the whole parse
// (callee-saved, never modified by the parse functions); cursor is LOC_IDX. The
// error labels bail to .exit_val, which resets sp to x29 so any recursion depth
// unwinds cleanly.

#include "uolt.inc"

.set STDOUT, 1
.set STDERR, 2

.set LOC_IDX,   64              // parse cursor
.set LOC_BUMP,  72             // bytes used in the arena
.set ARENAOFF,  80             // result arena
.set ARENASIZE, 4096
.set FRAME,     4192

.text
.globl uolt_main
uolt_main:
    sub     sp, sp, #4096
    sub     sp, sp, #96
    mov     x29, sp
    str     x30, [x29, #0]
    stp     x19, x20, [x29, #16]
    str     x21, [x29, #32]

    add     x19, x1, #8                // &argv[1]
    sub     x20, x0, #1                // operand count
    cbz     x20, .missing
    str     xzr, [x29, #LOC_IDX]
    str     xzr, [x29, #LOC_BUMP]

    bl      parse_or                   // x0 = result string pointer
    mov     x21, x0
    ldr     x9, [x29, #LOC_IDX]
    cmp     x9, x20                    // every token consumed?
    b.ne    syntax_error

    mov     x0, x21                    // print the value + newline
    bl      uolt_strlen
    mov     x2, x0
    mov     x1, x21
    mov     x0, #STDOUT
    bl      uolt_write
    mov     x0, #STDOUT
    adr     x1, nl
    mov     x2, #1
    bl      uolt_write

    mov     x0, x21                    // exit status: 1 if null or "0", else 0
    bl      val_false
    b       .exit_val

.missing:
    adr     x0, err_missing
    bl      err_puts
    mov     x0, #2
    b       .exit_val
syntax_error:
    adr     x0, err_syntax
    bl      err_puts
    mov     x0, #2
    b       .exit_val
arith_error:
    adr     x0, err_nonint
    bl      err_puts
    mov     x0, #2
    b       .exit_val
divzero_error:
    adr     x0, err_divzero
    bl      err_puts
    mov     x0, #2

// Common exit (x0 = code). Reset sp via x29 so an error bails from any depth.
.exit_val:
    mov     sp, x29
    ldr     x30, [x29, #0]
    ldp     x19, x20, [x29, #16]
    ldr     x21, [x29, #32]
    add     sp, sp, #4096
    add     sp, sp, #96
    ret

// ------------------------------- grammar -------------------------------------

// peek() -> x0 = current operand pointer, or 0 at end of input. Leaf.
peek:
    ldr     x0, [x29, #LOC_IDX]
    cmp     x0, x20
    b.hs    .pk_none
    ldr     x0, [x19, x0, lsl #3]
    ret
.pk_none:
    mov     x0, #0
    ret

// parse_or: and_e { '|' and_e }. Frame: [0]=lr [8]=lhs [16]=rhs.
parse_or:
    sub     sp, sp, #32
    str     x30, [sp, #0]
    bl      parse_and
    str     x0, [sp, #8]
.or_l:
    bl      peek
    cbz     x0, .or_ret
    adr     x1, op_or
    bl      streq
    cbz     x0, .or_ret
    ldr     x9, [x29, #LOC_IDX]
    add     x9, x9, #1
    str     x9, [x29, #LOC_IDX]
    bl      parse_and
    str     x0, [sp, #16]              // rhs
    ldr     x0, [sp, #8]               // lhs
    bl      val_false
    cbz     x0, .or_l                  // lhs true -> keep lhs
    ldr     x0, [sp, #16]              // lhs false -> result = rhs
    str     x0, [sp, #8]
    b       .or_l
.or_ret:
    ldr     x0, [sp, #8]
    ldr     x30, [sp, #0]
    add     sp, sp, #32
    ret

// parse_and: cmp_e { '&' cmp_e }.
parse_and:
    sub     sp, sp, #32
    str     x30, [sp, #0]
    bl      parse_cmp
    str     x0, [sp, #8]
.and_l:
    bl      peek
    cbz     x0, .and_ret
    adr     x1, op_and
    bl      streq
    cbz     x0, .and_ret
    ldr     x9, [x29, #LOC_IDX]
    add     x9, x9, #1
    str     x9, [x29, #LOC_IDX]
    bl      parse_cmp
    str     x0, [sp, #16]              // rhs
    ldr     x0, [sp, #8]               // lhs
    bl      val_false
    cbnz    x0, .and_zero              // lhs false -> 0
    ldr     x0, [sp, #16]              // rhs
    bl      val_false
    cbnz    x0, .and_zero              // rhs false -> 0
    b       .and_l                     // both true -> lhs stays
.and_zero:
    adr     x0, str_zero
    str     x0, [sp, #8]
    b       .and_l
.and_ret:
    ldr     x0, [sp, #8]
    ldr     x30, [sp, #0]
    add     sp, sp, #32
    ret

// parse_cmp: add_e { REL add_e } -> "1"/"0". Frame: [0]lr [8]lhs [16]op [24]rhs.
parse_cmp:
    sub     sp, sp, #32
    str     x30, [sp, #0]
    bl      parse_add
    str     x0, [sp, #8]
.cmp_l:
    bl      peek
    cbz     x0, .cmp_ret
    bl      which_cmp
    cbz     x0, .cmp_ret
    str     x0, [sp, #16]              // op
    ldr     x9, [x29, #LOC_IDX]
    add     x9, x9, #1
    str     x9, [x29, #LOC_IDX]
    bl      parse_add
    str     x0, [sp, #24]              // rhs
    ldr     x0, [sp, #8]               // lhs
    ldr     x1, [sp, #24]              // rhs
    ldr     x2, [sp, #16]              // op
    bl      do_compare
    cbz     x0, .cmp_false
    adr     x0, str_one
    str     x0, [sp, #8]
    b       .cmp_l
.cmp_false:
    adr     x0, str_zero
    str     x0, [sp, #8]
    b       .cmp_l
.cmp_ret:
    ldr     x0, [sp, #8]
    ldr     x30, [sp, #0]
    add     sp, sp, #32
    ret

// parse_add: mul_e { (+ -) mul_e }.
parse_add:
    sub     sp, sp, #32
    str     x30, [sp, #0]
    bl      parse_mul
    str     x0, [sp, #8]
.add_l:
    bl      peek
    cbz     x0, .add_ret
    bl      which_add
    cbz     x0, .add_ret
    str     x0, [sp, #16]
    ldr     x9, [x29, #LOC_IDX]
    add     x9, x9, #1
    str     x9, [x29, #LOC_IDX]
    bl      parse_mul
    str     x0, [sp, #24]
    ldr     x0, [sp, #8]
    ldr     x1, [sp, #24]
    ldr     x2, [sp, #16]
    bl      do_addsub
    bl      fmt_int_arena
    str     x0, [sp, #8]
    b       .add_l
.add_ret:
    ldr     x0, [sp, #8]
    ldr     x30, [sp, #0]
    add     sp, sp, #32
    ret

// parse_mul: prim { (* / %) prim }.
parse_mul:
    sub     sp, sp, #32
    str     x30, [sp, #0]
    bl      parse_prim
    str     x0, [sp, #8]
.mul_l:
    bl      peek
    cbz     x0, .mul_ret
    bl      which_mul
    cbz     x0, .mul_ret
    str     x0, [sp, #16]
    ldr     x9, [x29, #LOC_IDX]
    add     x9, x9, #1
    str     x9, [x29, #LOC_IDX]
    bl      parse_prim
    str     x0, [sp, #24]
    ldr     x0, [sp, #8]
    ldr     x1, [sp, #24]
    ldr     x2, [sp, #16]
    bl      do_muldiv
    bl      fmt_int_arena
    str     x0, [sp, #8]
    b       .mul_l
.mul_ret:
    ldr     x0, [sp, #8]
    ldr     x30, [sp, #0]
    add     sp, sp, #32
    ret

// parse_prim: '(' expr ')' | STRING. Frame: [0]lr [8]inner.
parse_prim:
    sub     sp, sp, #16
    str     x30, [sp, #0]
    bl      peek
    cbz     x0, .pp_syntax
    adr     x1, op_lp
    bl      streq
    cbz     x0, .pp_str
    ldr     x9, [x29, #LOC_IDX]
    add     x9, x9, #1
    str     x9, [x29, #LOC_IDX]
    bl      parse_or
    str     x0, [sp, #8]
    bl      peek
    cbz     x0, .pp_syntax
    adr     x1, op_rp
    bl      streq
    cbz     x0, .pp_syntax
    ldr     x9, [x29, #LOC_IDX]
    add     x9, x9, #1
    str     x9, [x29, #LOC_IDX]
    ldr     x0, [sp, #8]
    ldr     x30, [sp, #0]
    add     sp, sp, #16
    ret
.pp_str:
    ldr     x9, [x29, #LOC_IDX]
    ldr     x0, [x19, x9, lsl #3]
    add     x9, x9, #1
    str     x9, [x29, #LOC_IDX]
    ldr     x30, [sp, #0]
    add     sp, sp, #16
    ret
.pp_syntax:
    b       syntax_error

// ----------------------------- operator work ---------------------------------

// do_compare(x0=a, x1=b, x2=op) -> x0 truth. Numeric if both integers, else
// byte-lexical. Frame: [0]lr [8]a [16]b [24]op [32]aval.
do_compare:
    sub     sp, sp, #48
    str     x30, [sp, #0]
    str     x0, [sp, #8]
    str     x1, [sp, #16]
    str     x2, [sp, #24]
    ldr     x0, [sp, #8]
    bl      parse_intval
    cbnz    x1, .dc_str
    str     x0, [sp, #32]              // aval
    ldr     x0, [sp, #16]
    bl      parse_intval
    cbnz    x1, .dc_str
    ldr     x9, [sp, #32]              // aval
    cmp     x9, x0
    b.lt    .dc_neg
    b.gt    .dc_pos
    mov     x11, #0
    b       .dc_apply
.dc_neg:
    mov     x11, #-1
    b       .dc_apply
.dc_pos:
    mov     x11, #1
    b       .dc_apply
.dc_str:
    ldr     x0, [sp, #8]
    ldr     x1, [sp, #16]
    bl      strcmp3
    mov     x11, x0
.dc_apply:
    ldr     x2, [sp, #24]              // op
    cmp     x2, #1
    b.eq    .rl_lt
    cmp     x2, #2
    b.eq    .rl_le
    cmp     x2, #3
    b.eq    .rl_eq
    cmp     x2, #4
    b.eq    .rl_ne
    cmp     x2, #5
    b.eq    .rl_ge
    cmp     x11, #0                    // op 6: >
    b.gt    .rl_t
    b       .rl_f
.rl_lt:
    cmp     x11, #0
    b.lt    .rl_t
    b       .rl_f
.rl_le:
    cmp     x11, #0
    b.le    .rl_t
    b       .rl_f
.rl_eq:
    cmp     x11, #0
    b.eq    .rl_t
    b       .rl_f
.rl_ne:
    cmp     x11, #0
    b.ne    .rl_t
    b       .rl_f
.rl_ge:
    cmp     x11, #0
    b.ge    .rl_t
    b       .rl_f
.rl_t:
    mov     x0, #1
    ldr     x30, [sp, #0]
    add     sp, sp, #48
    ret
.rl_f:
    mov     x0, #0
    ldr     x30, [sp, #0]
    add     sp, sp, #48
    ret

// do_addsub(x0=a, x1=b, x2=op[1=+,2=-]) -> x0. Frame: [0]lr [8]b [16]op [24]aval.
do_addsub:
    sub     sp, sp, #32
    str     x30, [sp, #0]
    str     x1, [sp, #8]
    str     x2, [sp, #16]
    bl      parse_intval               // x0 = a
    cbnz    x1, .as_err
    str     x0, [sp, #24]
    ldr     x0, [sp, #8]
    bl      parse_intval               // x0 = b value
    cbnz    x1, .as_err
    ldr     x9, [sp, #24]              // aval
    ldr     x10, [sp, #16]             // op
    cmp     x10, #1
    b.eq    .as_add
    sub     x0, x9, x0
    b       .as_ret
.as_add:
    add     x0, x9, x0
.as_ret:
    ldr     x30, [sp, #0]
    add     sp, sp, #32
    ret
.as_err:
    b       arith_error

// do_muldiv(x0=a, x1=b, x2=op[1=*,2=/,3=%]) -> x0.
do_muldiv:
    sub     sp, sp, #32
    str     x30, [sp, #0]
    str     x1, [sp, #8]
    str     x2, [sp, #16]
    bl      parse_intval               // a
    cbnz    x1, .md_err
    str     x0, [sp, #24]
    ldr     x0, [sp, #8]
    bl      parse_intval               // b value
    cbnz    x1, .md_err
    ldr     x9, [sp, #24]              // aval
    ldr     x10, [sp, #16]             // op
    cmp     x10, #1
    b.eq    .md_mul
    cbz     x0, .md_divzero
    sdiv    x11, x9, x0                // quotient (toward zero)
    cmp     x10, #2
    b.eq    .md_q
    msub    x0, x11, x0, x9            // remainder = a - q*b
    b       .md_ret
.md_q:
    mov     x0, x11
    b       .md_ret
.md_mul:
    mul     x0, x9, x0
.md_ret:
    ldr     x30, [sp, #0]
    add     sp, sp, #32
    ret
.md_err:
    b       arith_error
.md_divzero:
    b       divzero_error

// ----------------------------- recognizers -----------------------------------

// which_cmp(x0) -> x0: 1 '<' 2 '<=' 3 '=' 4 '!=' 5 '>=' 6 '>' or 0. Leaf.
which_cmp:
    ldrb    w1, [x0]
    cmp     w1, #'<'
    b.eq    .wc_lt
    cmp     w1, #'>'
    b.eq    .wc_gt
    cmp     w1, #'='
    b.eq    .wc_eq
    cmp     w1, #'!'
    b.eq    .wc_ne
    mov     x0, #0
    ret
.wc_lt:
    ldrb    w1, [x0, #1]
    cbz     w1, .wc_r1
    cmp     w1, #'='
    b.ne    .wc_no
    ldrb    w1, [x0, #2]
    cbnz    w1, .wc_no
    mov     x0, #2
    ret
.wc_r1:
    mov     x0, #1
    ret
.wc_gt:
    ldrb    w1, [x0, #1]
    cbz     w1, .wc_r6
    cmp     w1, #'='
    b.ne    .wc_no
    ldrb    w1, [x0, #2]
    cbnz    w1, .wc_no
    mov     x0, #5
    ret
.wc_r6:
    mov     x0, #6
    ret
.wc_eq:
    ldrb    w1, [x0, #1]
    cbnz    w1, .wc_no
    mov     x0, #3
    ret
.wc_ne:
    ldrb    w1, [x0, #1]
    cmp     w1, #'='
    b.ne    .wc_no
    ldrb    w1, [x0, #2]
    cbnz    w1, .wc_no
    mov     x0, #4
    ret
.wc_no:
    mov     x0, #0
    ret

// which_add(x0) -> x0: 1 '+', 2 '-', or 0 (single-char tokens only). Leaf.
which_add:
    ldrb    w1, [x0, #1]
    cbnz    w1, .wa_no
    ldrb    w1, [x0]
    cmp     w1, #'+'
    b.eq    .wa1
    cmp     w1, #'-'
    b.eq    .wa2
.wa_no:
    mov     x0, #0
    ret
.wa1:
    mov     x0, #1
    ret
.wa2:
    mov     x0, #2
    ret

// which_mul(x0) -> x0: 1 '*', 2 '/', 3 '%', or 0. Leaf.
which_mul:
    ldrb    w1, [x0, #1]
    cbnz    w1, .wm_no
    ldrb    w1, [x0]
    cmp     w1, #'*'
    b.eq    .wm1
    cmp     w1, #'/'
    b.eq    .wm2
    cmp     w1, #'%'
    b.eq    .wm3
.wm_no:
    mov     x0, #0
    ret
.wm1:
    mov     x0, #1
    ret
.wm2:
    mov     x0, #2
    ret
.wm3:
    mov     x0, #3
    ret

// ------------------------------- utilities -----------------------------------

// val_false(x0 = s) -> x0 = 1 if empty or exactly "0", else 0.
val_false:
    ldrb    w1, [x0]
    cbz     w1, .vf_true
    adr     x1, str_zero
    b       streq
.vf_true:
    mov     x0, #1
    ret

// parse_intval(x0 = s) -> x0 = value, x1 = 0 ok / 1 error. Optional leading '-',
// then one or more digits, whole string. Leaf.
parse_intval:
    mov     x2, x0                     // cursor
    ldrb    w3, [x2]
    mov     w4, #0                     // negative flag
    cmp     w3, #'-'
    b.ne    .pv_start
    mov     w4, #1
    add     x2, x2, #1
.pv_start:
    ldrb    w3, [x2]
    cbz     w3, .pv_err
    mov     x0, #0
.pv_l:
    ldrb    w3, [x2]
    cbz     w3, .pv_done
    sub     w3, w3, #'0'
    cmp     w3, #9
    b.hi    .pv_err
    mov     x5, #10
    mul     x0, x0, x5
    add     x0, x0, w3, uxtw
    add     x2, x2, #1
    b       .pv_l
.pv_done:
    cbz     w4, .pv_ok
    neg     x0, x0
.pv_ok:
    mov     x1, #0
    ret
.pv_err:
    mov     x1, #1
    ret

// streq(x0, x1) -> x0 = 1 if equal else 0. Leaf.
streq:
    ldrb    w2, [x0]
    ldrb    w3, [x1]
    cmp     w2, w3
    b.ne    .sq_ne
    cbz     w2, .sq_eq
    add     x0, x0, #1
    add     x1, x1, #1
    b       streq
.sq_eq:
    mov     x0, #1
    ret
.sq_ne:
    mov     x0, #0
    ret

// strcmp3(x0, x1) -> x0 = -1 / 0 / 1 (unsigned byte order, C locale). Leaf.
strcmp3:
    ldrb    w2, [x0]
    ldrb    w3, [x1]
    cmp     w2, w3
    b.lo    .s3_neg
    b.hi    .s3_pos
    cbz     w2, .s3_eq
    add     x0, x0, #1
    add     x1, x1, #1
    b       strcmp3
.s3_eq:
    mov     x0, #0
    ret
.s3_neg:
    mov     x0, #-1
    ret
.s3_pos:
    mov     x0, #1
    ret

// fmt_int_arena(x0 = signed value) -> x0 = arena pointer (ASCIZ).
fmt_int_arena:
    sub     sp, sp, #48
    str     x30, [sp, #0]
    mov     x9, x0                     // value
    add     x10, sp, #40               // one-past the buffer
    strb    wzr, [x10]                 // NUL
    mov     w11, #0                    // negative flag
    cmp     x9, #0
    b.ge    .fi_pos
    mov     w11, #1
    neg     x9, x9
.fi_pos:
    mov     x12, #10
.fi_l:
    udiv    x13, x9, x12
    msub    x14, x13, x12, x9
    add     w14, w14, #'0'
    sub     x10, x10, #1
    strb    w14, [x10]
    mov     x9, x13
    cbnz    x9, .fi_l
    cbz     w11, .fi_sign
    sub     x10, x10, #1
    mov     w14, #'-'
    strb    w14, [x10]
.fi_sign:
    add     x9, sp, #40
    sub     x2, x9, x10                // length (excluding NUL)
    mov     x1, x10                    // src
    bl      arena_copy
    ldr     x30, [sp, #0]
    add     sp, sp, #48
    ret

// arena_copy(x1 = src, x2 = len) -> x0 = pointer to a NUL-terminated copy in the
// arena. A full arena is a runtime error. Leaf.
arena_copy:
    ldr     x9, [x29, #LOC_BUMP]
    add     x10, x9, x2
    add     x10, x10, #1
    cmp     x10, #ARENASIZE
    b.hi    arith_error                // arena exhausted
    add     x11, x29, #ARENAOFF
    add     x11, x11, x9               // dest = arena + bump
    mov     x12, x11                   // return pointer
    mov     x13, #0
.ac_l:
    cmp     x13, x2
    b.hs    .ac_done
    ldrb    w14, [x1, x13]
    strb    w14, [x11, x13]
    add     x13, x13, #1
    b       .ac_l
.ac_done:
    strb    wzr, [x11, x13]
    ldr     x9, [x29, #LOC_BUMP]
    add     x9, x9, x2
    add     x9, x9, #1
    str     x9, [x29, #LOC_BUMP]
    mov     x0, x12
    ret

// err_puts(x0 = ASCIZ): write a diagnostic to stderr. Saves lr.
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

op_or:       .asciz "|"
op_and:      .asciz "&"
op_lp:       .asciz "("
op_rp:       .asciz ")"
str_zero:    .asciz "0"
str_one:     .asciz "1"
nl:          .asciz "\n"
err_missing: .asciz "uolt-expr: missing operand\n"
err_syntax:  .asciz "uolt-expr: syntax error\n"
err_nonint:  .asciz "uolt-expr: non-integer argument\n"
err_divzero: .asciz "uolt-expr: division by zero\n"
