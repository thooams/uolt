// src/expr/expr.S - uolt-expr: the POSIX `expr` utility.
//
// expr EXPRESSION: evaluate an expression and write its value to stdout. Exit 0
// if the value is neither null nor "0", 1 if it is null or "0", 2 on an invalid
// expression or a runtime error (non-integer operand, division by zero).
//
// Operators, lowest precedence first (each is its own argv token, like the shell
// splits them; all left-associative):
//   |            expr1 if it is neither null nor 0, else expr2
//   &            expr1 if neither operand is null or 0, else 0
//   < <= = != >= >   relational (numeric if both operands are integers, else
//                    byte-lexical), yielding 1 (true) or 0 (false)
//   + -          integer addition / subtraction
//   * / %        integer multiply / divide / remainder (truncated toward zero)
//   ( expr )     grouping
//
// Deferred (documented, revisited when a regex engine lands): the `:` anchored
// BRE match operator. Overflow is not detected (64-bit wraparound). No heap
// (Principle IV): arithmetic results are formatted into a fixed stack arena.
//
// Called as uolt_main(argc, argv). r15 = operand base, r14 = operand count are
// held across the whole parse (callee-saved); the cursor is LOC_IDX.

#include "uolt.inc"

.set STDOUT, 1
.set STDERR, 2

// Kept below -40: the prologue pushes five callee-saved registers into
// [rbp-8 .. rbp-40].
.set LOC_IDX,    -56        // parse cursor
.set LOC_BUMP,   -64        // bytes used in the arena
.set ARENAOFF,   -4160      // result arena (ARENASIZE bytes, up to -64)
.set ARENASIZE,  4096
.set FRAME,      4224

.text
.globl uolt_main
uolt_main:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, FRAME
    cld

    lea     r15, [rsi + 8]              // &argv[1]
    lea     r14, [rdi - 1]              // operand count
    test    r14, r14
    jz      .missing
    mov     qword ptr [rbp + LOC_IDX], 0
    mov     qword ptr [rbp + LOC_BUMP], 0

    call    parse_or                    // rax = result string pointer
    mov     rbx, rax
    mov     rcx, [rbp + LOC_IDX]
    cmp     rcx, r14                    // every token consumed?
    jne     syntax_error

    // Print the value followed by a newline.
    mov     rdi, rbx
    call    uolt_strlen
    mov     rdx, rax
    mov     rsi, rbx
    mov     rdi, STDOUT
    call    uolt_write
    mov     rdi, STDOUT
    lea     rsi, [rip + nl]
    mov     rdx, 1
    call    uolt_write

    // Exit status: 1 if the value is null or "0", else 0.
    mov     rdi, rbx
    call    val_false
    jmp     .exit_val

.missing:
    lea     rdi, [rip + err_missing]
    call    err_puts
    mov     eax, 2
    jmp     .exit_val

syntax_error:
    lea     rdi, [rip + err_syntax]
    call    err_puts
    mov     eax, 2
    jmp     .exit_val
arith_error:
    lea     rdi, [rip + err_nonint]
    call    err_puts
    mov     eax, 2
    jmp     .exit_val
divzero_error:
    lea     rdi, [rip + err_divzero]
    call    err_puts
    mov     eax, 2

// Common exit (eax = code). Unwind via rbp so an error can bail from any depth.
.exit_val:
    lea     rsp, [rbp - 40]
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

// ------------------------------- grammar -------------------------------------

// peek() -> rax = current operand pointer, or 0 at end of input.
peek:
    mov     rax, [rbp + LOC_IDX]
    cmp     rax, r14
    jae     .pk_none
    mov     rax, [r15 + rax*8]
    ret
.pk_none:
    xor     eax, eax
    ret

// parse_or: and_e { '|' and_e }
parse_or:
    call    parse_and
.or_l:
    push    rax
    call    peek
    test    rax, rax
    jz      .or_pop
    mov     rdi, rax
    lea     rsi, [rip + op_or]
    call    streq
    test    eax, eax
    jz      .or_pop
    inc     qword ptr [rbp + LOC_IDX]
    call    parse_and
    push    rax                         // [lhs][rhs]
    mov     rdi, [rsp + 8]              // lhs
    call    val_false
    test    eax, eax
    jz      .or_takeL                   // lhs true -> keep lhs
    mov     rax, [rsp]                  // lhs false -> rhs
    add     rsp, 16
    jmp     .or_l
.or_takeL:
    mov     rax, [rsp + 8]
    add     rsp, 16
    jmp     .or_l
.or_pop:
    pop     rax
    ret

// parse_and: cmp_e { '&' cmp_e }
parse_and:
    call    parse_cmp
.and_l:
    push    rax
    call    peek
    test    rax, rax
    jz      .and_pop
    mov     rdi, rax
    lea     rsi, [rip + op_and]
    call    streq
    test    eax, eax
    jz      .and_pop
    inc     qword ptr [rbp + LOC_IDX]
    call    parse_cmp
    push    rax                         // [lhs][rhs]
    mov     rdi, [rsp + 8]              // lhs
    call    val_false
    test    eax, eax
    jnz     .and_zero
    mov     rdi, [rsp]                  // rhs
    call    val_false
    test    eax, eax
    jnz     .and_zero
    mov     rax, [rsp + 8]             // both true -> lhs
    add     rsp, 16
    jmp     .and_l
.and_zero:
    lea     rax, [rip + str_zero]
    add     rsp, 16
    jmp     .and_l
.and_pop:
    pop     rax
    ret

// parse_cmp: add_e { (< <= = != >= >) add_e } -> "1" / "0"
parse_cmp:
    call    parse_add
.cmp_l:
    push    rax
    call    peek
    test    rax, rax
    jz      .cmp_pop
    mov     rdi, rax
    call    which_cmp
    test    eax, eax
    jz      .cmp_pop
    push    rax                         // [lhs][op]
    inc     qword ptr [rbp + LOC_IDX]
    call    parse_add
    push    rax                         // [lhs][op][rhs]
    mov     rdi, [rsp + 16]             // lhs
    mov     rsi, [rsp]                  // rhs
    mov     edx, [rsp + 8]              // op
    call    do_compare
    add     rsp, 24
    test    eax, eax
    jz      .cmp_false
    lea     rax, [rip + str_one]
    jmp     .cmp_l
.cmp_false:
    lea     rax, [rip + str_zero]
    jmp     .cmp_l
.cmp_pop:
    pop     rax
    ret

// parse_add: mul_e { (+ -) mul_e }
parse_add:
    call    parse_mul
.add_l:
    push    rax
    call    peek
    test    rax, rax
    jz      .add_pop
    mov     rdi, rax
    call    which_add
    test    eax, eax
    jz      .add_pop
    push    rax                         // [lhs][op]
    inc     qword ptr [rbp + LOC_IDX]
    call    parse_mul
    push    rax                         // [lhs][op][rhs]
    mov     rdi, [rsp + 16]
    mov     rsi, [rsp]
    mov     edx, [rsp + 8]
    call    do_addsub                   // rax = integer result
    add     rsp, 24
    mov     rdi, rax
    call    fmt_int_arena
    jmp     .add_l
.add_pop:
    pop     rax
    ret

// parse_mul: prim { (* / %) prim }
parse_mul:
    call    parse_prim
.mul_l:
    push    rax
    call    peek
    test    rax, rax
    jz      .mul_pop
    mov     rdi, rax
    call    which_mul
    test    eax, eax
    jz      .mul_pop
    push    rax                         // [lhs][op]
    inc     qword ptr [rbp + LOC_IDX]
    call    parse_prim
    push    rax                         // [lhs][op][rhs]
    mov     rdi, [rsp + 16]
    mov     rsi, [rsp]
    mov     edx, [rsp + 8]
    call    do_muldiv
    add     rsp, 24
    mov     rdi, rax
    call    fmt_int_arena
    jmp     .mul_l
.mul_pop:
    pop     rax
    ret

// parse_prim: '(' expr ')' | STRING
parse_prim:
    call    peek
    test    rax, rax
    jz      syntax_error
    mov     rdi, rax
    lea     rsi, [rip + op_lp]
    call    streq
    test    eax, eax
    jz      .pp_str
    inc     qword ptr [rbp + LOC_IDX]
    call    parse_or
    push    rax
    call    peek
    test    rax, rax
    jz      syntax_error
    mov     rdi, rax
    lea     rsi, [rip + op_rp]
    call    streq
    test    eax, eax
    jz      syntax_error
    inc     qword ptr [rbp + LOC_IDX]
    pop     rax
    ret
.pp_str:
    mov     rax, [rbp + LOC_IDX]
    mov     rax, [r15 + rax*8]
    inc     qword ptr [rbp + LOC_IDX]
    ret

// ----------------------------- operator work ---------------------------------

// do_compare(rdi=a, rsi=b, edx=op) -> eax truth. Numeric if both integers, else
// byte-lexical.
do_compare:
    push    rbx
    mov     ebx, edx
    push    rsi
    push    rdi                         // [a][b]  (a on top)
    call    parse_intval
    jc      .dc_str
    mov     r8, rax
    mov     rdi, [rsp + 8]              // b
    call    parse_intval
    jc      .dc_str
    mov     r9, rax
    add     rsp, 16
    cmp     r8, r9
    jl      .dc_neg
    jg      .dc_pos
    xor     ecx, ecx
    jmp     .dc_apply
.dc_neg:
    mov     ecx, -1
    jmp     .dc_apply
.dc_pos:
    mov     ecx, 1
    jmp     .dc_apply
.dc_str:
    mov     rdi, [rsp]                  // a
    mov     rsi, [rsp + 8]              // b
    add     rsp, 16
    call    strcmp3
    mov     ecx, eax
.dc_apply:
    mov     edx, ebx
    cmp     edx, 1
    je      .rl_lt
    cmp     edx, 2
    je      .rl_le
    cmp     edx, 3
    je      .rl_eq
    cmp     edx, 4
    je      .rl_ne
    cmp     edx, 5
    je      .rl_ge
    test    ecx, ecx                    // op 6: >
    jg      .rl_t
    jmp     .rl_f
.rl_lt:
    test    ecx, ecx
    js      .rl_t
    jmp     .rl_f
.rl_le:
    test    ecx, ecx
    jle     .rl_t
    jmp     .rl_f
.rl_eq:
    test    ecx, ecx
    jz      .rl_t
    jmp     .rl_f
.rl_ne:
    test    ecx, ecx
    jnz     .rl_t
    jmp     .rl_f
.rl_ge:
    test    ecx, ecx
    jns     .rl_t
    jmp     .rl_f
.rl_t:
    mov     eax, 1
    pop     rbx
    ret
.rl_f:
    xor     eax, eax
    pop     rbx
    ret

// do_addsub(rdi=a, rsi=b, edx=op[1=+,2=-]) -> rax = integer result.
do_addsub:
    mov     r10d, edx
    mov     r11, rsi
    call    parse_intval
    jc      arith_error
    mov     r8, rax
    mov     rdi, r11
    call    parse_intval
    jc      arith_error
    mov     r9, rax
    cmp     r10d, 1
    je      .as_add
    mov     rax, r8
    sub     rax, r9
    ret
.as_add:
    mov     rax, r8
    add     rax, r9
    ret

// do_muldiv(rdi=a, rsi=b, edx=op[1=*,2=/,3=%]) -> rax = integer result.
do_muldiv:
    mov     r10d, edx
    mov     r11, rsi
    call    parse_intval
    jc      arith_error
    mov     r8, rax
    mov     rdi, r11
    call    parse_intval
    jc      arith_error
    mov     r9, rax
    cmp     r10d, 1
    je      .md_mul
    test    r9, r9
    jz      divzero_error
    mov     rax, r8
    cqo
    idiv    r9                          // rax = quotient, rdx = remainder
    cmp     r10d, 2
    je      .md_ret
    mov     rax, rdx                    // '%'
.md_ret:
    ret
.md_mul:
    mov     rax, r8
    imul    rax, r9
    ret

// ----------------------------- recognizers -----------------------------------

// which_cmp(rdi) -> eax: 1 '<' 2 '<=' 3 '=' 4 '!=' 5 '>=' 6 '>' or 0.
which_cmp:
    movzx   eax, byte ptr [rdi]
    cmp     al, '<'
    je      .wc_lt
    cmp     al, '>'
    je      .wc_gt
    cmp     al, '='
    je      .wc_eq
    cmp     al, '!'
    je      .wc_ne
    xor     eax, eax
    ret
.wc_lt:
    cmp     byte ptr [rdi + 1], 0
    je      .wc_r1
    cmp     byte ptr [rdi + 1], '='
    jne     .wc_no
    cmp     byte ptr [rdi + 2], 0
    jne     .wc_no
    mov     eax, 2
    ret
.wc_r1:
    mov     eax, 1
    ret
.wc_gt:
    cmp     byte ptr [rdi + 1], 0
    je      .wc_r6
    cmp     byte ptr [rdi + 1], '='
    jne     .wc_no
    cmp     byte ptr [rdi + 2], 0
    jne     .wc_no
    mov     eax, 5
    ret
.wc_r6:
    mov     eax, 6
    ret
.wc_eq:
    cmp     byte ptr [rdi + 1], 0
    jne     .wc_no
    mov     eax, 3
    ret
.wc_ne:
    cmp     byte ptr [rdi + 1], '='
    jne     .wc_no
    cmp     byte ptr [rdi + 2], 0
    jne     .wc_no
    mov     eax, 4
    ret
.wc_no:
    xor     eax, eax
    ret

// which_add(rdi) -> eax: 1 '+', 2 '-', or 0 (only for the single-char tokens).
which_add:
    cmp     byte ptr [rdi + 1], 0
    jne     .wa_no
    movzx   eax, byte ptr [rdi]
    cmp     al, '+'
    je      .wa1
    cmp     al, '-'
    je      .wa2
.wa_no:
    xor     eax, eax
    ret
.wa1:
    mov     eax, 1
    ret
.wa2:
    mov     eax, 2
    ret

// which_mul(rdi) -> eax: 1 '*', 2 '/', 3 '%', or 0.
which_mul:
    cmp     byte ptr [rdi + 1], 0
    jne     .wm_no
    movzx   eax, byte ptr [rdi]
    cmp     al, '*'
    je      .wm1
    cmp     al, '/'
    je      .wm2
    cmp     al, '%'
    je      .wm3
.wm_no:
    xor     eax, eax
    ret
.wm1:
    mov     eax, 1
    ret
.wm2:
    mov     eax, 2
    ret
.wm3:
    mov     eax, 3
    ret

// ------------------------------- utilities -----------------------------------

// val_false(rdi = s) -> eax = 1 if the string is empty or exactly "0", else 0.
val_false:
    cmp     byte ptr [rdi], 0
    je      .vf_true
    lea     rsi, [rip + str_zero]
    call    streq
    ret
.vf_true:
    mov     eax, 1
    ret

// parse_intval(rdi = s) -> rax = value, CF set on error. Optional leading '-',
// then one or more digits, whole string.
parse_intval:
    movzx   ecx, byte ptr [rdi]
    xor     edx, edx                    // dl = negative flag
    cmp     cl, '-'
    jne     .pv_start
    mov     dl, 1
    inc     rdi
.pv_start:
    movzx   ecx, byte ptr [rdi]
    test    cl, cl
    jz      .pv_err
    xor     rax, rax
.pv_l:
    movzx   ecx, byte ptr [rdi]
    test    cl, cl
    jz      .pv_done
    sub     cl, '0'
    cmp     cl, 9
    ja      .pv_err
    imul    rax, rax, 10
    movzx   rcx, cl
    add     rax, rcx
    inc     rdi
    jmp     .pv_l
.pv_done:
    test    dl, dl
    jz      .pv_ok
    neg     rax
.pv_ok:
    clc
    ret
.pv_err:
    stc
    ret

// streq(rdi, rsi) -> eax = 1 if equal else 0.
streq:
    mov     al, [rdi]
    cmp     al, [rsi]
    jne     .sq_ne
    test    al, al
    jz      .sq_eq
    inc     rdi
    inc     rsi
    jmp     streq
.sq_eq:
    mov     eax, 1
    ret
.sq_ne:
    xor     eax, eax
    ret

// strcmp3(rdi, rsi) -> eax = -1 / 0 / 1 (unsigned byte order, C locale).
strcmp3:
    movzx   eax, byte ptr [rdi]
    movzx   ecx, byte ptr [rsi]
    cmp     al, cl
    jb      .s3_neg
    ja      .s3_pos
    test    al, al
    jz      .s3_eq
    inc     rdi
    inc     rsi
    jmp     strcmp3
.s3_eq:
    xor     eax, eax
    ret
.s3_neg:
    mov     eax, -1
    ret
.s3_pos:
    mov     eax, 1
    ret

// fmt_int_arena(rdi = signed value) -> rax = arena pointer (ASCIZ).
fmt_int_arena:
    sub     rsp, 32
    mov     rax, rdi
    lea     rcx, [rsp + 24]
    mov     byte ptr [rcx], 0
    xor     r8d, r8d
    test    rax, rax
    jns     .fi_pos
    mov     r8d, 1
    neg     rax
.fi_pos:
    mov     r9, 10
.fi_l:
    xor     rdx, rdx
    div     r9
    add     dl, '0'
    dec     rcx
    mov     [rcx], dl
    test    rax, rax
    jnz     .fi_l
    test    r8d, r8d
    jz      .fi_sign
    dec     rcx
    mov     byte ptr [rcx], '-'
.fi_sign:
    lea     rdx, [rsp + 24]
    sub     rdx, rcx                    // length (excluding NUL)
    mov     rsi, rcx
    call    arena_copy
    add     rsp, 32
    ret

// arena_copy(rsi = src, rdx = len) -> rax = pointer to a NUL-terminated copy in
// the arena. A full arena is a runtime error.
arena_copy:
    mov     rcx, [rbp + LOC_BUMP]
    lea     rax, [rcx + rdx]
    inc     rax
    cmp     rax, ARENASIZE
    ja      arith_error                 // arena exhausted
    lea     rdi, [rbp + ARENAOFF]
    add     rdi, rcx
    mov     r10, rdi                    // return pointer
    push    rsi
    push    rdx
    mov     rcx, rdx
    rep     movsb
    mov     byte ptr [rdi], 0
    pop     rdx
    pop     rsi
    mov     rcx, [rbp + LOC_BUMP]
    add     rcx, rdx
    inc     rcx
    mov     [rbp + LOC_BUMP], rcx
    mov     rax, r10
    ret

// err_puts(rdi = ASCIZ): write a diagnostic to stderr.
err_puts:
    mov     r10, rdi
    call    uolt_strlen
    mov     rdx, rax
    mov     rsi, r10
    mov     rdi, STDERR
    jmp     uolt_write

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
