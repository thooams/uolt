// src/test/test.S - uolt-test: the POSIX `test` utility (and `[`).
//
// test expression / [ expression ]: evaluate a conditional expression and exit 0
// (true), 1 (false), or 2 (syntax error). When invoked under the name `[` (via a
// symlink), the final argument must be `]`, which is stripped before evaluation.
//
// Primaries:
//   string:  -n S  -z S  S1 = S2  S1 != S2  (and a lone S is true if non-empty)
//   integer: n1 -eq|-ne|-gt|-ge|-lt|-le n2
//   file:    -e -f -d -s -r -w -x -h -L -p -S -b -c -g -u -k  FILE
// Operators: ! expr,  expr1 -a expr2,  expr1 -o expr2,  ( expr )  (-o lowest
// precedence, then -a, then !, with () grouping).
//
// Evaluation follows the POSIX argument-count algorithm for 0-4 arguments (which
// pins the semantics of corner cases the grammar alone would mis-handle, e.g. a
// bare `!` or `=` used as a string), and a recursive-descent grammar for five or
// more. A syntax error prints a diagnostic to stderr and exits 2.
//
// Deferred (documented): `-t FD` (needs a terminal ioctl, a different mechanism
// than the stat/access primaries here) and the GNU string `<`/`>` comparisons.
//
// No heap (Principle IV): only fixed stack locals; the stat/access syscalls own
// their own scratch buffers in sys/<os>/. Called as uolt_main(argc, argv).

#include "uolt.inc"

.set STDERR, 2

// Stack locals. Kept below -40 because the prologue pushes five callee-saved
// registers (rbx, r12-r15) into [rbp-8 .. rbp-40]; overlapping them there would
// corrupt the values the epilogue restores.
.set LOC_IDX,     -56       // cursor for the general grammar
.set LOC_BOP,     -64       // saved binary opcode across the two integer parses
.set LOC_IV1,     -72       // first parsed integer
.set LOC_BRK,     -80       // byte: invoked as `[` (1) or `test` (0)
.set FRAME,       128

// Registers held across the whole evaluation (callee-saved): r15 = operand
// vector base, r14 = operand count. Helper routines read them but never write
// them; each keeps its own live state in rbx (saved/restored per helper) or a
// stack local.

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

    mov     r12, rdi                    // argc
    mov     r13, rsi                    // argv

    // Detect the `[` invocation from argv[0]'s basename.
    mov     rdi, [r13]
    call    basename_ptr
    mov     rdi, rax
    lea     rsi, [rip + lit_lb]
    call    test_streq
    mov     [rbp + LOC_BRK], al

    // Operands = &argv[1], count = argc - 1.
    lea     r15, [r13 + 8]
    lea     r14, [r12 - 1]

    // `[` mode: the last operand must be `]`; strip it.
    cmp     byte ptr [rbp + LOC_BRK], 0
    je      .no_bracket
    test    r14, r14
    jz      .brk_err
    mov     rax, r14
    dec     rax
    mov     rdi, [r15 + rax*8]
    lea     rsi, [rip + lit_rb]
    call    test_streq
    test    eax, eax
    jz      .brk_err
    dec     r14                         // drop the trailing `]`
.no_bracket:

    // Dispatch on the operand count (POSIX algorithm for 0-4, grammar for >=5).
    test    r14, r14
    jz      .res_false                  // 0 operands -> false
    cmp     r14, 1
    je      .d1
    cmp     r14, 2
    je      .d2
    cmp     r14, 3
    je      .d3
    cmp     r14, 4
    je      .d4
    call    general_eval
    jmp     .finish
.d1:
    mov     rdi, [r15]
    call    one_argument
    jmp     .finish
.d2:
    mov     rdi, r15
    call    two_args
    jmp     .finish
.d3:
    mov     rdi, r15
    call    three_args
    jmp     .finish
.d4:
    mov     rdi, r15
    call    four_args
.finish:
    // eax = truth (0/1) -> exit code (true -> 0, false -> 1).
    test    eax, eax
    setz    al
    movzx   eax, al
    jmp     .exit_val
.res_false:
    mov     eax, 1
    jmp     .exit_val
.brk_err:
    jmp     syntax_error

// Common exit: eax already holds the exit code. Unwind via rbp (the grammar may
// be many calls deep when a syntax error longjmps here).
.exit_val:
    lea     rsp, [rbp - 40]
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

// syntax_error: diagnose and exit 2. Never returns (unwinds through .exit_val).
syntax_error:
    lea     rdi, [rip + err_syntax]
    call    err_puts
    mov     eax, 2
    jmp     .exit_val

// ------------------------- argument-count helpers ----------------------------

// one_argument(rdi = string) -> eax = 1 if non-empty else 0.
one_argument:
    call    uolt_strlen
    test    rax, rax
    setne   al
    movzx   eax, al
    ret

// two_args(rdi = base of 2 operands) -> eax truth.
two_args:
    push    rbx
    mov     rbx, rdi
    mov     rdi, [rbx]
    lea     rsi, [rip + lit_not]
    call    test_streq
    test    eax, eax
    jz      .ta_unop
    mov     rdi, [rbx + 8]              // ! S  -> negate the one-arg test of S
    call    one_argument
    xor     eax, 1
    jmp     .ta_ret
.ta_unop:
    mov     rdi, [rbx]
    call    is_unop
    test    eax, eax
    jz      .ta_err
    mov     esi, eax
    mov     rdi, [rbx + 8]
    call    apply_unop
.ta_ret:
    pop     rbx
    ret
.ta_err:
    jmp     syntax_error

// three_args(rdi = base of 3 operands) -> eax truth.
three_args:
    push    rbx
    mov     rbx, rdi
    mov     rdi, [rbx + 8]              // binary operator in the middle?
    call    is_binop
    test    eax, eax
    jz      .thr_notbin
    mov     edx, eax
    mov     rdi, [rbx]
    mov     rsi, [rbx + 16]
    call    apply_binop
    jmp     .thr_ret
.thr_notbin:
    mov     rdi, [rbx]                  // ! b c  -> negate two_args(b, c)
    lea     rsi, [rip + lit_not]
    call    test_streq
    test    eax, eax
    jz      .thr_paren
    lea     rdi, [rbx + 8]
    call    two_args
    xor     eax, 1
    jmp     .thr_ret
.thr_paren:
    mov     rdi, [rbx]                  // ( b )  -> one_argument(b)
    lea     rsi, [rip + lit_lp]
    call    test_streq
    test    eax, eax
    jz      .thr_err
    mov     rdi, [rbx + 16]
    lea     rsi, [rip + lit_rp]
    call    test_streq
    test    eax, eax
    jz      .thr_err
    mov     rdi, [rbx + 8]
    call    one_argument
.thr_ret:
    pop     rbx
    ret
.thr_err:
    jmp     syntax_error

// four_args(rdi = base of 4 operands) -> eax truth.
four_args:
    push    rbx
    mov     rbx, rdi
    mov     rdi, [rbx]                  // ! b c d  -> negate three_args(b, c, d)
    lea     rsi, [rip + lit_not]
    call    test_streq
    test    eax, eax
    jz      .fa_paren
    lea     rdi, [rbx + 8]
    call    three_args
    xor     eax, 1
    jmp     .fa_ret
.fa_paren:
    mov     rdi, [rbx]                  // ( b c )  -> two_args(b, c)
    lea     rsi, [rip + lit_lp]
    call    test_streq
    test    eax, eax
    jz      .fa_general
    mov     rdi, [rbx + 24]
    lea     rsi, [rip + lit_rp]
    call    test_streq
    test    eax, eax
    jz      .fa_general
    lea     rdi, [rbx + 8]
    call    two_args
    jmp     .fa_ret
.fa_general:
    call    general_eval
.fa_ret:
    pop     rbx
    ret

// ------------------------- recursive-descent grammar -------------------------
// Cursor in LOC_IDX; operands at r15[0 .. r14). or_expr (-o) has the lowest
// precedence, then and_expr (-a), then factor (! and parentheses), then primary.

general_eval:
    mov     qword ptr [rbp + LOC_IDX], 0
    call    or_expr
    mov     rcx, [rbp + LOC_IDX]
    cmp     rcx, r14                    // all operands consumed?
    jne     syntax_error
    ret

// peek() -> rax = current operand pointer, or 0 when the cursor is at the end.
peek:
    mov     rax, [rbp + LOC_IDX]
    cmp     rax, r14
    jae     .pk_none
    mov     rax, [r15 + rax*8]
    ret
.pk_none:
    xor     eax, eax
    ret

or_expr:
    call    and_expr
.or_l:
    push    rax
    call    peek
    test    rax, rax
    jz      .or_done
    mov     rdi, rax
    lea     rsi, [rip + lit_or]
    call    test_streq
    test    eax, eax
    jz      .or_done
    inc     qword ptr [rbp + LOC_IDX]
    call    and_expr
    pop     rcx
    or      eax, ecx
    jmp     .or_l
.or_done:
    pop     rax
    ret

and_expr:
    call    factor
.and_l:
    push    rax
    call    peek
    test    rax, rax
    jz      .and_done
    mov     rdi, rax
    lea     rsi, [rip + lit_and]
    call    test_streq
    test    eax, eax
    jz      .and_done
    inc     qword ptr [rbp + LOC_IDX]
    call    factor
    pop     rcx
    and     eax, ecx
    jmp     .and_l
.and_done:
    pop     rax
    ret

factor:
    call    peek
    test    rax, rax
    jz      syntax_error
    mov     rdi, rax
    lea     rsi, [rip + lit_not]
    call    test_streq
    test    eax, eax
    jz      .fac_paren
    inc     qword ptr [rbp + LOC_IDX]
    call    factor
    xor     eax, 1
    ret
.fac_paren:
    call    peek
    mov     rdi, rax
    lea     rsi, [rip + lit_lp]
    call    test_streq
    test    eax, eax
    jz      .fac_prim
    inc     qword ptr [rbp + LOC_IDX]
    call    or_expr
    push    rax
    call    peek
    test    rax, rax
    jz      syntax_error
    mov     rdi, rax
    lea     rsi, [rip + lit_rp]
    call    test_streq
    test    eax, eax
    jz      syntax_error
    inc     qword ptr [rbp + LOC_IDX]
    pop     rax
    ret
.fac_prim:
    call    primary
    ret

// primary(): one of  a OP b  |  UNOP a  |  a  (single string), consuming 3, 2,
// or 1 operands from the cursor.
primary:
    // Binary form: is the token after the current one a binary operator?
    mov     rax, [rbp + LOC_IDX]
    lea     rcx, [rax + 1]
    cmp     rcx, r14
    jae     .prim_unary
    mov     rdi, [r15 + rcx*8]
    call    is_binop
    test    eax, eax
    jz      .prim_unary
    mov     rcx, [rbp + LOC_IDX]        // need a third operand
    lea     rdx, [rcx + 2]
    cmp     rdx, r14
    jae     syntax_error
    mov     edx, eax                    // opcode
    mov     rdi, [r15 + rcx*8]          // a
    mov     rsi, [r15 + rcx*8 + 16]     // b
    add     qword ptr [rbp + LOC_IDX], 3
    call    apply_binop
    ret
.prim_unary:
    // Unary form: current token is a file/string unary operator with an operand.
    mov     rax, [rbp + LOC_IDX]
    mov     rdi, [r15 + rax*8]
    call    is_unop
    test    eax, eax
    jz      .prim_single
    mov     rcx, [rbp + LOC_IDX]
    lea     rdx, [rcx + 1]
    cmp     rdx, r14
    jae     .prim_single                // operator with no operand -> string test
    mov     esi, eax
    mov     rcx, [rbp + LOC_IDX]
    mov     rdi, [r15 + rcx*8 + 8]
    add     qword ptr [rbp + LOC_IDX], 2
    call    apply_unop
    ret
.prim_single:
    mov     rax, [rbp + LOC_IDX]
    mov     rdi, [r15 + rax*8]
    inc     qword ptr [rbp + LOC_IDX]
    call    one_argument
    ret

// ------------------------------- primaries -----------------------------------

// apply_unop(esi = opcode, rdi = operand) -> eax truth.
apply_unop:
    cmp     esi, 1
    je      .u_n
    cmp     esi, 2
    je      .u_z
    cmp     esi, 3
    je      .u_e
    cmp     esi, 4
    je      .u_f
    cmp     esi, 5
    je      .u_d
    cmp     esi, 6
    je      .u_r
    cmp     esi, 7
    je      .u_w
    cmp     esi, 8
    je      .u_x
    cmp     esi, 9
    je      .u_s
    cmp     esi, 10
    je      .u_lnk
    cmp     esi, 11
    je      .u_lnk
    cmp     esi, 12
    je      .u_fifo
    cmp     esi, 13
    je      .u_sock
    cmp     esi, 14
    je      .u_blk
    cmp     esi, 15
    je      .u_chr
    cmp     esi, 16
    je      .u_gid
    cmp     esi, 17
    je      .u_uid
    cmp     esi, 18
    je      .u_vtx
    xor     eax, eax
    ret
.u_n:
    call    uolt_strlen
    test    rax, rax
    setne   al
    movzx   eax, al
    ret
.u_z:
    call    uolt_strlen
    test    rax, rax
    sete    al
    movzx   eax, al
    ret
.u_e:
    call    uolt_statmode
    test    rax, rax
    jns     .u_true
    jmp     .u_false
.u_f:
    mov     esi, S_IFREG
    jmp     .u_type
.u_d:
    mov     esi, S_IFDIR
    jmp     .u_type
.u_fifo:
    mov     esi, S_IFIFO
    jmp     .u_type
.u_sock:
    mov     esi, S_IFSOCK
    jmp     .u_type
.u_blk:
    mov     esi, S_IFBLK
    jmp     .u_type
.u_chr:
    mov     esi, S_IFCHR
    jmp     .u_type
.u_type:
    // stat (follow) then compare (st_mode & S_IFMT) to esi.
    push    rsi
    call    uolt_statmode
    pop     rsi
    test    rax, rax
    js      .u_false
    and     eax, S_IFMT
    cmp     eax, esi
    je      .u_true
    jmp     .u_false
.u_lnk:
    call    uolt_lstatmode
    test    rax, rax
    js      .u_false
    and     eax, S_IFMT
    cmp     eax, S_IFLNK
    je      .u_true
    jmp     .u_false
.u_s:
    call    uolt_statsize
    test    rax, rax
    jg      .u_true                     // exists and size > 0
    jmp     .u_false
.u_r:
    mov     esi, R_OK
    jmp     .u_acc
.u_w:
    mov     esi, W_OK
    jmp     .u_acc
.u_x:
    mov     esi, X_OK
.u_acc:
    call    uolt_access
    test    rax, rax
    jz      .u_true
    jmp     .u_false
.u_gid:
    mov     esi, S_ISGID
    jmp     .u_bit
.u_uid:
    mov     esi, S_ISUID
    jmp     .u_bit
.u_vtx:
    mov     esi, S_ISVTX
.u_bit:
    push    rsi
    call    uolt_statmode
    pop     rsi
    test    rax, rax
    js      .u_false
    test    eax, esi
    jnz     .u_true
    jmp     .u_false
.u_true:
    mov     eax, 1
    ret
.u_false:
    xor     eax, eax
    ret

// apply_binop(rdi = a, esi = b, edx = opcode) -> eax truth.
apply_binop:
    cmp     edx, 1
    je      .b_eq
    cmp     edx, 2
    je      .b_ne
    mov     [rbp + LOC_BOP], edx
    mov     rbx, rsi                    // preserve b across the first parse
    push    rbx
    call    test_atoi                   // rdi = a
    jc      .b_ierr
    mov     [rbp + LOC_IV1], rax
    mov     rdi, rbx                    // b
    call    test_atoi
    pop     rbx
    jc      .b_ierr
    mov     r8, rax                     // v2
    mov     r9, [rbp + LOC_IV1]         // v1
    mov     edx, [rbp + LOC_BOP]
    cmp     edx, 3
    je      .i_eq
    cmp     edx, 4
    je      .i_ne
    cmp     edx, 5
    je      .i_gt
    cmp     edx, 6
    je      .i_ge
    cmp     edx, 7
    je      .i_lt
    cmp     r9, r8                      // -le
    jle     .i_true
    jmp     .i_false
.i_eq:
    cmp     r9, r8
    je      .i_true
    jmp     .i_false
.i_ne:
    cmp     r9, r8
    jne     .i_true
    jmp     .i_false
.i_gt:
    cmp     r9, r8
    jg      .i_true
    jmp     .i_false
.i_ge:
    cmp     r9, r8
    jge     .i_true
    jmp     .i_false
.i_lt:
    cmp     r9, r8
    jl      .i_true
    jmp     .i_false
.i_true:
    mov     eax, 1
    ret
.i_false:
    xor     eax, eax
    ret
.b_eq:
    call    test_streq
    ret
.b_ne:
    call    test_streq
    xor     eax, 1
    ret
.b_ierr:
    jmp     syntax_error

// --------------------------- operator recognizers ----------------------------

// is_unop(rdi = s) -> eax = opcode (1..18) or 0. Matches "-<letter>" exactly.
is_unop:
    cmp     byte ptr [rdi], '-'
    jne     .uo_no
    cmp     byte ptr [rdi + 2], 0
    jne     .uo_no
    movzx   eax, byte ptr [rdi + 1]
    cmp     al, 'n'
    je      .uo1
    cmp     al, 'z'
    je      .uo2
    cmp     al, 'e'
    je      .uo3
    cmp     al, 'f'
    je      .uo4
    cmp     al, 'd'
    je      .uo5
    cmp     al, 'r'
    je      .uo6
    cmp     al, 'w'
    je      .uo7
    cmp     al, 'x'
    je      .uo8
    cmp     al, 's'
    je      .uo9
    cmp     al, 'h'
    je      .uo10
    cmp     al, 'L'
    je      .uo11
    cmp     al, 'p'
    je      .uo12
    cmp     al, 'S'
    je      .uo13
    cmp     al, 'b'
    je      .uo14
    cmp     al, 'c'
    je      .uo15
    cmp     al, 'g'
    je      .uo16
    cmp     al, 'u'
    je      .uo17
    cmp     al, 'k'
    je      .uo18
.uo_no:
    xor     eax, eax
    ret
.uo1:
    mov     eax, 1
    ret
.uo2:
    mov     eax, 2
    ret
.uo3:
    mov     eax, 3
    ret
.uo4:
    mov     eax, 4
    ret
.uo5:
    mov     eax, 5
    ret
.uo6:
    mov     eax, 6
    ret
.uo7:
    mov     eax, 7
    ret
.uo8:
    mov     eax, 8
    ret
.uo9:
    mov     eax, 9
    ret
.uo10:
    mov     eax, 10
    ret
.uo11:
    mov     eax, 11
    ret
.uo12:
    mov     eax, 12
    ret
.uo13:
    mov     eax, 13
    ret
.uo14:
    mov     eax, 14
    ret
.uo15:
    mov     eax, 15
    ret
.uo16:
    mov     eax, 16
    ret
.uo17:
    mov     eax, 17
    ret
.uo18:
    mov     eax, 18
    ret

// is_binop(rdi = s) -> eax = opcode (1..8) or 0.
//   1 =   2 !=   3 -eq  4 -ne  5 -gt  6 -ge  7 -lt  8 -le
is_binop:
    cmp     byte ptr [rdi], '='
    jne     .bo_ne
    cmp     byte ptr [rdi + 1], 0
    jne     .bo_no
    mov     eax, 1
    ret
.bo_ne:
    cmp     byte ptr [rdi], '!'
    jne     .bo_dash
    cmp     byte ptr [rdi + 1], '='
    jne     .bo_no
    cmp     byte ptr [rdi + 2], 0
    jne     .bo_no
    mov     eax, 2
    ret
.bo_dash:
    cmp     byte ptr [rdi], '-'
    jne     .bo_no
    cmp     byte ptr [rdi + 3], 0
    jne     .bo_no
    movzx   ecx, byte ptr [rdi + 1]
    movzx   edx, byte ptr [rdi + 2]
    cmp     cl, 'e'
    jne     .bo_n
    cmp     dl, 'q'
    jne     .bo_no
    mov     eax, 3
    ret
.bo_n:
    cmp     cl, 'n'
    jne     .bo_g
    cmp     dl, 'e'
    jne     .bo_no
    mov     eax, 4
    ret
.bo_g:
    cmp     cl, 'g'
    jne     .bo_l
    cmp     dl, 't'
    je      .bo_gt
    cmp     dl, 'e'
    je      .bo_ge
    jmp     .bo_no
.bo_gt:
    mov     eax, 5
    ret
.bo_ge:
    mov     eax, 6
    ret
.bo_l:
    cmp     cl, 'l'
    jne     .bo_no
    cmp     dl, 't'
    je      .bo_lt
    cmp     dl, 'e'
    je      .bo_le
    jmp     .bo_no
.bo_lt:
    mov     eax, 7
    ret
.bo_le:
    mov     eax, 8
    ret
.bo_no:
    xor     eax, eax
    ret

// ------------------------------- utilities -----------------------------------

// test_streq(rdi = a, rsi = b) -> eax = 1 if the strings are equal else 0.
test_streq:
    mov     al, [rdi]
    cmp     al, [rsi]
    jne     .se_ne
    test    al, al
    jz      .se_eq
    inc     rdi
    inc     rsi
    jmp     test_streq
.se_eq:
    mov     eax, 1
    ret
.se_ne:
    xor     eax, eax
    ret

// test_atoi(rdi = s) -> rax = value, CF set on error (empty or non-digit).
// Accepts an optional leading '+' or '-'; the whole string must be digits.
test_atoi:
    movzx   ecx, byte ptr [rdi]
    xor     r8, r8
    cmp     cl, '-'
    jne     .ai_plus
    mov     r8, 1
    inc     rdi
    jmp     .ai_start
.ai_plus:
    cmp     cl, '+'
    jne     .ai_start
    inc     rdi
.ai_start:
    xor     rax, rax
    xor     r9, r9
.ai_l:
    movzx   ecx, byte ptr [rdi]
    test    cl, cl
    jz      .ai_done
    sub     cl, '0'
    cmp     cl, 9
    ja      .ai_err
    imul    rax, rax, 10
    movzx   rcx, cl
    add     rax, rcx
    mov     r9, 1
    inc     rdi
    jmp     .ai_l
.ai_done:
    test    r9, r9
    jz      .ai_err
    test    r8, r8
    jz      .ai_ok
    neg     rax
.ai_ok:
    clc
    ret
.ai_err:
    stc
    ret

// basename_ptr(rdi = path) -> rax = pointer to the last path component.
basename_ptr:
    mov     rax, rdi
    mov     rcx, rdi
.bn_l:
    movzx   edx, byte ptr [rcx]
    test    dl, dl
    jz      .bn_done
    cmp     dl, '/'
    jne     .bn_next
    lea     rax, [rcx + 1]
.bn_next:
    inc     rcx
    jmp     .bn_l
.bn_done:
    ret

// err_puts(rdi = ASCIZ): write a diagnostic to stderr.
err_puts:
    mov     r10, rdi
    call    uolt_strlen
    mov     rdx, rax
    mov     rsi, r10
    mov     rdi, STDERR
    jmp     uolt_write

lit_lb:      .asciz "["
lit_rb:      .asciz "]"
lit_not:     .asciz "!"
lit_lp:      .asciz "("
lit_rp:      .asciz ")"
lit_and:     .asciz "-a"
lit_or:      .asciz "-o"
err_syntax:  .asciz "uolt-test: syntax error\n"
