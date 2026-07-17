// src/test/arm64/test.S - uolt-test: the POSIX `test` utility (and `[`), aarch64.
//
// test expression / [ expression ]: evaluate a conditional expression and exit 0
// (true), 1 (false), or 2 (syntax error). Under the name `[` the final argument
// must be `]`, stripped before evaluation. Mirrors the x86_64 body.
//
// Evaluation follows the POSIX argument-count algorithm for 0-4 arguments and a
// recursive-descent grammar for five or more. `-t FD` and the GNU string `<`/`>`
// comparisons are deferred. No heap (Principle IV): fixed stack locals; the
// stat/access wrappers own their scratch in sys/<os>/.
//
// x19 = operand vector base, x20 = operand count, held across the whole
// evaluation (callee-saved, never written by helpers). Each helper keeps its live
// state in x21 (saved/restored) or a stack local. Error labels bail to .exit_val,
// which resets sp to x29 so any recursion depth unwinds.

#include "uolt.inc"

.set STDERR, 2

.set LOC_IDX,  40               // cursor for the general grammar
.set LOC_BOP,  48              // saved binary opcode across the two integer parses
.set LOC_IV1,  56             // first parsed integer
.set LOC_BRK,  64            // byte: invoked as `[` (1) or `test` (0)
.set FRAME,    128

.text
.globl uolt_main
uolt_main:
    sub     sp, sp, #128
    mov     x29, sp
    str     x30, [x29, #0]
    stp     x19, x20, [x29, #16]
    str     x21, [x29, #32]

    // Detect the `[` invocation from argv[0]'s basename.
    mov     x9, x0                     // argc
    add     x19, x1, #8                // operand base = &argv[1]
    sub     x20, x9, #1                // count = argc - 1
    ldr     x0, [x1]                   // argv[0]
    bl      basename_ptr
    adr     x1, lit_lb
    bl      test_streq
    strb    w0, [x29, #LOC_BRK]

    // `[` mode: the last operand must be `]`; strip it.
    ldrb    w9, [x29, #LOC_BRK]
    cbz     w9, .no_bracket
    cbz     x20, .brk_err
    sub     x9, x20, #1
    ldr     x0, [x19, x9, lsl #3]
    adr     x1, lit_rb
    bl      test_streq
    cbz     x0, .brk_err
    sub     x20, x20, #1
.no_bracket:
    cbz     x20, .res_false            // 0 operands -> false
    cmp     x20, #1
    b.eq    .d1
    cmp     x20, #2
    b.eq    .d2
    cmp     x20, #3
    b.eq    .d3
    cmp     x20, #4
    b.eq    .d4
    bl      general_eval
    b       .finish
.d1:
    ldr     x0, [x19]
    bl      one_argument
    b       .finish
.d2:
    mov     x0, x19
    bl      two_args
    b       .finish
.d3:
    mov     x0, x19
    bl      three_args
    b       .finish
.d4:
    mov     x0, x19
    bl      four_args
.finish:
    cmp     x0, #0                     // truth -> exit code (true -> 0, false -> 1)
    cset    w0, eq
    b       .exit_val
.res_false:
    mov     x0, #1
    b       .exit_val
.brk_err:
    b       syntax_error

// Common exit (x0 = code). Reset sp via x29 so a deep syntax error unwinds.
.exit_val:
    mov     sp, x29
    ldr     x30, [x29, #0]
    ldp     x19, x20, [x29, #16]
    ldr     x21, [x29, #32]
    add     sp, sp, #128
    ret

syntax_error:
    adr     x0, err_syntax
    bl      err_puts
    mov     x0, #2
    b       .exit_val

// ------------------------- argument-count helpers ----------------------------

// one_argument(x0 = string) -> x0 = 1 if non-empty else 0.
one_argument:
    stp     x29, x30, [sp, #-16]!
    bl      uolt_strlen
    cmp     x0, #0
    cset    w0, ne
    ldp     x29, x30, [sp], #16
    ret

// two_args(x0 = base of 2 operands) -> x0 truth.
two_args:
    sub     sp, sp, #16
    stp     x21, x30, [sp, #0]
    mov     x21, x0
    ldr     x0, [x21]
    adr     x1, lit_not
    bl      test_streq
    cbz     x0, .ta_unop
    ldr     x0, [x21, #8]              // ! S -> negate one_argument(S)
    bl      one_argument
    eor     x0, x0, #1
    b       .ta_ret
.ta_unop:
    ldr     x0, [x21]
    bl      is_unop
    cbz     x0, .ta_err
    mov     x1, x0                     // opcode
    ldr     x0, [x21, #8]             // operand
    bl      apply_unop
.ta_ret:
    ldp     x21, x30, [sp], #16
    ret
.ta_err:
    b       syntax_error

// three_args(x0 = base of 3 operands) -> x0 truth.
three_args:
    sub     sp, sp, #16
    stp     x21, x30, [sp, #0]
    mov     x21, x0
    ldr     x0, [x21, #8]              // binary operator in the middle?
    bl      is_binop
    cbz     x0, .thr_notbin
    mov     x2, x0                     // opcode
    ldr     x0, [x21]                  // a
    ldr     x1, [x21, #16]            // b
    bl      apply_binop
    b       .thr_ret
.thr_notbin:
    ldr     x0, [x21]                  // ! b c -> negate two_args(b, c)
    adr     x1, lit_not
    bl      test_streq
    cbz     x0, .thr_paren
    add     x0, x21, #8
    bl      two_args
    eor     x0, x0, #1
    b       .thr_ret
.thr_paren:
    ldr     x0, [x21]                  // ( b ) -> one_argument(b)
    adr     x1, lit_lp
    bl      test_streq
    cbz     x0, .thr_err
    ldr     x0, [x21, #16]
    adr     x1, lit_rp
    bl      test_streq
    cbz     x0, .thr_err
    ldr     x0, [x21, #8]
    bl      one_argument
.thr_ret:
    ldp     x21, x30, [sp], #16
    ret
.thr_err:
    b       syntax_error

// four_args(x0 = base of 4 operands) -> x0 truth.
four_args:
    sub     sp, sp, #16
    stp     x21, x30, [sp, #0]
    mov     x21, x0
    ldr     x0, [x21]                  // ! b c d -> negate three_args(b, c, d)
    adr     x1, lit_not
    bl      test_streq
    cbz     x0, .fa_paren
    add     x0, x21, #8
    bl      three_args
    eor     x0, x0, #1
    b       .fa_ret
.fa_paren:
    ldr     x0, [x21]                  // ( b c ) -> two_args(b, c)
    adr     x1, lit_lp
    bl      test_streq
    cbz     x0, .fa_general
    ldr     x0, [x21, #24]
    adr     x1, lit_rp
    bl      test_streq
    cbz     x0, .fa_general
    add     x0, x21, #8
    bl      two_args
    b       .fa_ret
.fa_general:
    bl      general_eval
.fa_ret:
    ldp     x21, x30, [sp], #16
    ret

// ------------------------- recursive-descent grammar -------------------------

general_eval:
    stp     x29, x30, [sp, #-16]!
    str     xzr, [x29, #LOC_IDX]
    bl      or_expr
    ldr     x9, [x29, #LOC_IDX]
    cmp     x9, x20                    // all operands consumed?
    b.ne    .ge_syntax
    ldp     x29, x30, [sp], #16
    ret
.ge_syntax:
    b       syntax_error

// peek() -> x0 = current operand pointer, or 0 at end. Leaf.
peek:
    ldr     x0, [x29, #LOC_IDX]
    cmp     x0, x20
    b.hs    .pk_none
    ldr     x0, [x19, x0, lsl #3]
    ret
.pk_none:
    mov     x0, #0
    ret

or_expr:
    sub     sp, sp, #16
    str     x30, [sp, #0]
    bl      and_expr
    str     x0, [sp, #8]
.or_l:
    bl      peek
    cbz     x0, .or_done
    adr     x1, lit_or
    bl      test_streq
    cbz     x0, .or_done
    ldr     x9, [x29, #LOC_IDX]
    add     x9, x9, #1
    str     x9, [x29, #LOC_IDX]
    bl      and_expr
    ldr     x9, [sp, #8]
    orr     x0, x0, x9
    str     x0, [sp, #8]
    b       .or_l
.or_done:
    ldr     x0, [sp, #8]
    ldr     x30, [sp, #0]
    add     sp, sp, #16
    ret

and_expr:
    sub     sp, sp, #16
    str     x30, [sp, #0]
    bl      factor
    str     x0, [sp, #8]
.and_l:
    bl      peek
    cbz     x0, .and_done
    adr     x1, lit_and
    bl      test_streq
    cbz     x0, .and_done
    ldr     x9, [x29, #LOC_IDX]
    add     x9, x9, #1
    str     x9, [x29, #LOC_IDX]
    bl      factor
    ldr     x9, [sp, #8]
    and     x0, x0, x9
    str     x0, [sp, #8]
    b       .and_l
.and_done:
    ldr     x0, [sp, #8]
    ldr     x30, [sp, #0]
    add     sp, sp, #16
    ret

factor:
    sub     sp, sp, #16
    str     x30, [sp, #0]
    bl      peek
    cbz     x0, .fac_syntax
    adr     x1, lit_not
    bl      test_streq
    cbz     x0, .fac_paren
    ldr     x9, [x29, #LOC_IDX]
    add     x9, x9, #1
    str     x9, [x29, #LOC_IDX]
    bl      factor
    eor     x0, x0, #1
    ldr     x30, [sp, #0]
    add     sp, sp, #16
    ret
.fac_paren:
    bl      peek
    adr     x1, lit_lp
    bl      test_streq
    cbz     x0, .fac_prim
    ldr     x9, [x29, #LOC_IDX]
    add     x9, x9, #1
    str     x9, [x29, #LOC_IDX]
    bl      or_expr
    str     x0, [sp, #8]
    bl      peek
    cbz     x0, .fac_syntax
    adr     x1, lit_rp
    bl      test_streq
    cbz     x0, .fac_syntax
    ldr     x9, [x29, #LOC_IDX]
    add     x9, x9, #1
    str     x9, [x29, #LOC_IDX]
    ldr     x0, [sp, #8]
    ldr     x30, [sp, #0]
    add     sp, sp, #16
    ret
.fac_prim:
    bl      primary
    ldr     x30, [sp, #0]
    add     sp, sp, #16
    ret
.fac_syntax:
    b       syntax_error

// primary(): a OP b | UNOP a | a, consuming 3, 2, or 1 operands.
primary:
    sub     sp, sp, #16
    str     x30, [sp, #0]
    ldr     x9, [x29, #LOC_IDX]        // token after current is a binary op?
    add     x10, x9, #1
    cmp     x10, x20
    b.hs    .prim_unary
    ldr     x0, [x19, x10, lsl #3]
    bl      is_binop
    cbz     x0, .prim_unary
    ldr     x9, [x29, #LOC_IDX]        // need a third operand
    add     x11, x9, #2
    cmp     x11, x20
    b.hs    .prim_syntax
    mov     x2, x0                     // opcode
    ldr     x0, [x19, x9, lsl #3]      // a
    add     x12, x9, #2
    ldr     x1, [x19, x12, lsl #3]     // b
    add     x9, x9, #3
    str     x9, [x29, #LOC_IDX]
    bl      apply_binop
    ldr     x30, [sp, #0]
    add     sp, sp, #16
    ret
.prim_unary:
    ldr     x9, [x29, #LOC_IDX]
    ldr     x0, [x19, x9, lsl #3]      // current token
    bl      is_unop
    cbz     x0, .prim_single
    ldr     x9, [x29, #LOC_IDX]
    add     x10, x9, #1
    cmp     x10, x20
    b.hs    .prim_single               // operator with no operand -> string test
    mov     x1, x0                     // opcode
    ldr     x9, [x29, #LOC_IDX]
    add     x12, x9, #1
    ldr     x0, [x19, x12, lsl #3]     // operand
    add     x9, x9, #2
    str     x9, [x29, #LOC_IDX]
    bl      apply_unop
    ldr     x30, [sp, #0]
    add     sp, sp, #16
    ret
.prim_single:
    ldr     x9, [x29, #LOC_IDX]
    ldr     x0, [x19, x9, lsl #3]
    add     x9, x9, #1
    str     x9, [x29, #LOC_IDX]
    bl      one_argument
    ldr     x30, [sp, #0]
    add     sp, sp, #16
    ret
.prim_syntax:
    b       syntax_error

// ------------------------------- primaries -----------------------------------

// apply_unop(x0 = operand, x1 = opcode) -> x0 truth.
apply_unop:
    sub     sp, sp, #16
    stp     x21, x30, [sp, #0]
    cmp     x1, #1
    b.eq    .u_n
    cmp     x1, #2
    b.eq    .u_z
    cmp     x1, #3
    b.eq    .u_e
    cmp     x1, #4
    b.eq    .u_f
    cmp     x1, #5
    b.eq    .u_d
    cmp     x1, #6
    b.eq    .u_r
    cmp     x1, #7
    b.eq    .u_w
    cmp     x1, #8
    b.eq    .u_x
    cmp     x1, #9
    b.eq    .u_s
    cmp     x1, #10
    b.eq    .u_lnk
    cmp     x1, #11
    b.eq    .u_lnk
    cmp     x1, #12
    b.eq    .u_fifo
    cmp     x1, #13
    b.eq    .u_sock
    cmp     x1, #14
    b.eq    .u_blk
    cmp     x1, #15
    b.eq    .u_chr
    cmp     x1, #16
    b.eq    .u_gid
    cmp     x1, #17
    b.eq    .u_uid
    cmp     x1, #18
    b.eq    .u_vtx
    mov     x0, #0
    b       .u_ret
.u_n:
    bl      uolt_strlen
    cmp     x0, #0
    cset    w0, ne
    b       .u_ret
.u_z:
    bl      uolt_strlen
    cmp     x0, #0
    cset    w0, eq
    b       .u_ret
.u_e:
    bl      uolt_statmode
    cmp     x0, #0
    b.ge    .u_true
    b       .u_false
.u_f:
    mov     x21, #S_IFREG
    b       .u_type
.u_d:
    mov     x21, #S_IFDIR
    b       .u_type
.u_fifo:
    mov     x21, #S_IFIFO
    b       .u_type
.u_sock:
    mov     x21, #S_IFSOCK
    b       .u_type
.u_blk:
    mov     x21, #S_IFBLK
    b       .u_type
.u_chr:
    mov     x21, #S_IFCHR
.u_type:
    bl      uolt_statmode              // x0 = operand -> st_mode
    cmp     x0, #0
    b.lt    .u_false
    and     w0, w0, #S_IFMT
    cmp     w0, w21
    b.eq    .u_true
    b       .u_false
.u_lnk:
    bl      uolt_lstatmode
    cmp     x0, #0
    b.lt    .u_false
    and     w0, w0, #S_IFMT
    cmp     w0, #S_IFLNK
    b.eq    .u_true
    b       .u_false
.u_s:
    bl      uolt_statsize
    cmp     x0, #0
    b.gt    .u_true
    b       .u_false
.u_r:
    mov     x1, #R_OK
    b       .u_acc
.u_w:
    mov     x1, #W_OK
    b       .u_acc
.u_x:
    mov     x1, #X_OK
.u_acc:
    bl      uolt_access                // x0 = path, x1 = mode
    cmp     x0, #0
    b.eq    .u_true
    b       .u_false
.u_gid:
    mov     x21, #S_ISGID
    b       .u_bit
.u_uid:
    mov     x21, #S_ISUID
    b       .u_bit
.u_vtx:
    mov     x21, #S_ISVTX
.u_bit:
    bl      uolt_statmode
    cmp     x0, #0
    b.lt    .u_false
    and     w0, w0, w21
    cbnz    w0, .u_true
    b       .u_false
.u_true:
    mov     x0, #1
    b       .u_ret
.u_false:
    mov     x0, #0
.u_ret:
    ldp     x21, x30, [sp], #16
    ret

// apply_binop(x0 = a, x1 = b, x2 = opcode) -> x0 truth.
apply_binop:
    cmp     x2, #1
    b.eq    .b_eq
    cmp     x2, #2
    b.eq    .b_ne
    // integer comparison
    sub     sp, sp, #16
    str     x30, [sp, #0]
    str     x2, [x29, #LOC_BOP]
    str     x1, [sp, #8]               // b (survives the first parse)
    bl      test_atoi                  // x0 = a
    cbnz    x1, .b_ierr
    str     x0, [x29, #LOC_IV1]        // v1
    ldr     x0, [sp, #8]               // b
    bl      test_atoi
    cbnz    x1, .b_ierr
    mov     x8, x0                     // v2
    ldr     x9, [x29, #LOC_IV1]        // v1
    ldr     x2, [x29, #LOC_BOP]
    cmp     x2, #3
    b.eq    .i_eq
    cmp     x2, #4
    b.eq    .i_ne
    cmp     x2, #5
    b.eq    .i_gt
    cmp     x2, #6
    b.eq    .i_ge
    cmp     x2, #7
    b.eq    .i_lt
    cmp     x9, x8                     // -le
    b.le    .i_true
    b       .i_false
.i_eq:
    cmp     x9, x8
    b.eq    .i_true
    b       .i_false
.i_ne:
    cmp     x9, x8
    b.ne    .i_true
    b       .i_false
.i_gt:
    cmp     x9, x8
    b.gt    .i_true
    b       .i_false
.i_ge:
    cmp     x9, x8
    b.ge    .i_true
    b       .i_false
.i_lt:
    cmp     x9, x8
    b.lt    .i_true
    b       .i_false
.i_true:
    mov     x0, #1
    ldr     x30, [sp, #0]
    add     sp, sp, #16
    ret
.i_false:
    mov     x0, #0
    ldr     x30, [sp, #0]
    add     sp, sp, #16
    ret
.b_eq:
    b       test_streq
.b_ne:
    sub     sp, sp, #16
    str     x30, [sp, #0]
    bl      test_streq
    eor     x0, x0, #1
    ldr     x30, [sp, #0]
    add     sp, sp, #16
    ret
.b_ierr:
    b       syntax_error

// --------------------------- operator recognizers ----------------------------

// is_unop(x0 = s) -> x0 = opcode (1..18) or 0. Matches "-<letter>" exactly. Leaf.
is_unop:
    ldrb    w1, [x0]
    cmp     w1, #'-'
    b.ne    .uo_no
    ldrb    w1, [x0, #2]
    cbnz    w1, .uo_no
    ldrb    w1, [x0, #1]
    cmp     w1, #'n'
    b.eq    .uo1
    cmp     w1, #'z'
    b.eq    .uo2
    cmp     w1, #'e'
    b.eq    .uo3
    cmp     w1, #'f'
    b.eq    .uo4
    cmp     w1, #'d'
    b.eq    .uo5
    cmp     w1, #'r'
    b.eq    .uo6
    cmp     w1, #'w'
    b.eq    .uo7
    cmp     w1, #'x'
    b.eq    .uo8
    cmp     w1, #'s'
    b.eq    .uo9
    cmp     w1, #'h'
    b.eq    .uo10
    cmp     w1, #'L'
    b.eq    .uo11
    cmp     w1, #'p'
    b.eq    .uo12
    cmp     w1, #'S'
    b.eq    .uo13
    cmp     w1, #'b'
    b.eq    .uo14
    cmp     w1, #'c'
    b.eq    .uo15
    cmp     w1, #'g'
    b.eq    .uo16
    cmp     w1, #'u'
    b.eq    .uo17
    cmp     w1, #'k'
    b.eq    .uo18
.uo_no:
    mov     x0, #0
    ret
.uo1:
    mov     x0, #1
    ret
.uo2:
    mov     x0, #2
    ret
.uo3:
    mov     x0, #3
    ret
.uo4:
    mov     x0, #4
    ret
.uo5:
    mov     x0, #5
    ret
.uo6:
    mov     x0, #6
    ret
.uo7:
    mov     x0, #7
    ret
.uo8:
    mov     x0, #8
    ret
.uo9:
    mov     x0, #9
    ret
.uo10:
    mov     x0, #10
    ret
.uo11:
    mov     x0, #11
    ret
.uo12:
    mov     x0, #12
    ret
.uo13:
    mov     x0, #13
    ret
.uo14:
    mov     x0, #14
    ret
.uo15:
    mov     x0, #15
    ret
.uo16:
    mov     x0, #16
    ret
.uo17:
    mov     x0, #17
    ret
.uo18:
    mov     x0, #18
    ret

// is_binop(x0 = s) -> x0 = opcode (1..8) or 0. Leaf.
//   1 =   2 !=   3 -eq  4 -ne  5 -gt  6 -ge  7 -lt  8 -le
is_binop:
    ldrb    w2, [x0]
    cmp     w2, #'='
    b.ne    .bo_ne
    ldrb    w1, [x0, #1]
    cbnz    w1, .bo_no
    mov     x0, #1
    ret
.bo_ne:
    cmp     w2, #'!'
    b.ne    .bo_dash
    ldrb    w1, [x0, #1]
    cmp     w1, #'='
    b.ne    .bo_no
    ldrb    w1, [x0, #2]
    cbnz    w1, .bo_no
    mov     x0, #2
    ret
.bo_dash:
    cmp     w2, #'-'
    b.ne    .bo_no
    ldrb    w1, [x0, #3]
    cbnz    w1, .bo_no
    ldrb    w3, [x0, #1]
    ldrb    w4, [x0, #2]
    cmp     w3, #'e'
    b.ne    .bo_n
    cmp     w4, #'q'
    b.ne    .bo_no
    mov     x0, #3
    ret
.bo_n:
    cmp     w3, #'n'
    b.ne    .bo_g
    cmp     w4, #'e'
    b.ne    .bo_no
    mov     x0, #4
    ret
.bo_g:
    cmp     w3, #'g'
    b.ne    .bo_l
    cmp     w4, #'t'
    b.eq    .bo_gt
    cmp     w4, #'e'
    b.eq    .bo_ge
    b       .bo_no
.bo_gt:
    mov     x0, #5
    ret
.bo_ge:
    mov     x0, #6
    ret
.bo_l:
    cmp     w3, #'l'
    b.ne    .bo_no
    cmp     w4, #'t'
    b.eq    .bo_lt
    cmp     w4, #'e'
    b.eq    .bo_le
    b       .bo_no
.bo_lt:
    mov     x0, #7
    ret
.bo_le:
    mov     x0, #8
    ret
.bo_no:
    mov     x0, #0
    ret

// ------------------------------- utilities -----------------------------------

// test_streq(x0 = a, x1 = b) -> x0 = 1 if equal else 0. Leaf.
test_streq:
    ldrb    w2, [x0]
    ldrb    w3, [x1]
    cmp     w2, w3
    b.ne    .se_ne
    cbz     w2, .se_eq
    add     x0, x0, #1
    add     x1, x1, #1
    b       test_streq
.se_eq:
    mov     x0, #1
    ret
.se_ne:
    mov     x0, #0
    ret

// test_atoi(x0 = s) -> x0 = value, x1 = 0 ok / 1 error. Optional leading +/-, the
// whole string must be digits. Leaf.
test_atoi:
    mov     x2, x0                     // cursor
    ldrb    w3, [x2]
    mov     x4, #0                     // negative flag
    cmp     w3, #'-'
    b.ne    .ai_plus
    mov     x4, #1
    add     x2, x2, #1
    b       .ai_start
.ai_plus:
    cmp     w3, #'+'
    b.ne    .ai_start
    add     x2, x2, #1
.ai_start:
    mov     x0, #0                     // value
    mov     x5, #0                     // digit seen
.ai_l:
    ldrb    w3, [x2]
    cbz     w3, .ai_done
    sub     w3, w3, #'0'
    cmp     w3, #9
    b.hi    .ai_err
    mov     x6, #10
    mul     x0, x0, x6
    add     x0, x0, w3, uxtw
    mov     x5, #1
    add     x2, x2, #1
    b       .ai_l
.ai_done:
    cbz     x5, .ai_err
    cbz     x4, .ai_ok
    neg     x0, x0
.ai_ok:
    mov     x1, #0
    ret
.ai_err:
    mov     x1, #1
    ret

// basename_ptr(x0 = path) -> x0 = pointer to the last path component. Leaf.
basename_ptr:
    mov     x1, x0                     // result
    mov     x2, x0                     // cursor
.bn_l:
    ldrb    w3, [x2]
    cbz     w3, .bn_done
    cmp     w3, #'/'
    b.ne    .bn_next
    add     x1, x2, #1
.bn_next:
    add     x2, x2, #1
    b       .bn_l
.bn_done:
    mov     x0, x1
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

lit_lb:      .asciz "["
lit_rb:      .asciz "]"
lit_not:     .asciz "!"
lit_lp:      .asciz "("
lit_rp:      .asciz ")"
lit_and:     .asciz "-a"
lit_or:      .asciz "-o"
err_syntax:  .asciz "uolt-test: syntax error\n"
