// src/chmod/chmod.S - the POSIX `chmod` utility.
//
// chmod MODE file...: change each file's permission bits. MODE is either an octal
// number (e.g. 755, 0644) or a symbolic expression: comma-separated clauses of
// the form [ugoa...][+-=][rwxX...] (e.g. u+x, go-w, a=r, +X). For a symbolic
// mode the file's current mode is fetched with stat; X adds execute only if the
// file is a directory or already has some execute bit. The setuid/setgid/sticky
// letters (s, t) are out of scope in v1.
//
// A file that cannot be changed yields a stderr diagnostic and sets the exit
// status to 1, without stopping the remaining operands. No heap (Principle IV).
//
// Called as uolt_main(argc in rdi, argv in rsi) by the per-OS entry shim.
//
// Stack locals: [-48] = symbolic pattern ptr (0 = octal), [-56] = octal mode,
//   [-64] = exit status.

#include "uolt.inc"

.set STDERR, 2

.set LOC_SYM,   -48
.set LOC_MODE,  -56
.set LOC_STAT,  -64
.set LOC_UMASK, -72

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
    sub     rsp, 48
    mov     qword ptr [rbp + LOC_STAT], 0

    mov     r12, rdi
    dec     r12                         // operand count
    lea     r13, [rsi + 8]

    // read the umask (needed for who-less symbolic clauses): set to 0, restore
    xor     rdi, rdi
    call    uolt_umask
    mov     [rbp + LOC_UMASK], rax
    mov     rdi, rax
    call    uolt_umask
    cmp     r12, 2
    jl      .usage

    // classify the mode operand: leading digit -> octal, else symbolic
    mov     rbx, [r13]
    movzx   eax, byte ptr [rbx]
    sub     al, '0'
    cmp     al, 7
    ja      .symbolic
    // octal
    mov     qword ptr [rbp + LOC_SYM], 0
    xor     r15, r15
    xor     rcx, rcx
.pm:
    movzx   eax, byte ptr [rbx]
    test    al, al
    jz      .pm_done
    sub     al, '0'
    cmp     al, 7
    ja      .bad_mode
    shl     r15, 3
    movzx   rax, al
    add     r15, rax
    mov     rcx, 1
    inc     rbx
    jmp     .pm
.pm_done:
    test    rcx, rcx
    jz      .bad_mode
    mov     [rbp + LOC_MODE], r15
    jmp     .files
.symbolic:
    mov     [rbp + LOC_SYM], rbx

.files:
    add     r13, 8                      // advance past the mode operand
    dec     r12

.loop:
    test    r12, r12
    jz      .fin
    mov     rbx, [r13]                  // path
    cmp     qword ptr [rbp + LOC_SYM], 0
    jne     .sym_file
    // octal: chmod(path, mode)
    mov     rdi, rbx
    mov     rsi, [rbp + LOC_MODE]
    call    uolt_chmod
    test    rax, rax
    js      .diag
    jmp     .next
.sym_file:
    mov     rdi, rbx                    // stat the current mode
    call    uolt_statmode
    test    rax, rax
    js      .diag
    mov     rdi, rax                    // current mode
    mov     rsi, [rbp + LOC_SYM]
    call    apply_sym                   // -> rax = new mode
    and     rax, 07777                  // permission + special bits only
    mov     rsi, rax
    mov     rdi, rbx
    call    uolt_chmod
    test    rax, rax
    js      .diag
    jmp     .next
.diag:
    mov     qword ptr [rbp + LOC_STAT], 1
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
    mov     rax, [rbp + LOC_STAT]
    jmp     .ret
.bad_mode:
    lea     rdi, [rip + err_mode]
    call    err_puts
    mov     rax, 1
    jmp     .ret
.usage:
    lea     rdi, [rip + err_usage]
    call    err_puts
    mov     rax, 1
.ret:
    add     rsp, 48
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

// apply_sym(rdi = current mode, rsi = pattern) -> rax = new mode.
apply_sym:
    push    rbx
    push    r12
    push    r13
    mov     r12, rdi                    // working mode
    mov     r13, rsi                    // pattern cursor
.as_clause:
    movzx   eax, byte ptr [r13]
    test    al, al
    jz      .as_done
    xor     rbx, rbx                    // who bits (4=u, 2=g, 1=o)
.as_who:
    movzx   eax, byte ptr [r13]
    cmp     al, 'u'
    jne     1f
    or      rbx, 4
    inc     r13
    jmp     .as_who
1:
    cmp     al, 'g'
    jne     2f
    or      rbx, 2
    inc     r13
    jmp     .as_who
2:
    cmp     al, 'o'
    jne     3f
    or      rbx, 1
    inc     r13
    jmp     .as_who
3:
    cmp     al, 'a'
    jne     .as_op
    or      rbx, 7
    inc     r13
    jmp     .as_who
.as_op:
    mov     r11, rbx                    // nonzero = an explicit who was given
    test    rbx, rbx
    jnz     4f
    mov     rbx, 7                      // no who -> all (but masked by umask below)
4:
    movzx   r8d, byte ptr [r13]         // operator + - =
    inc     r13
    xor     r9, r9                      // perm bits (rwx)
    xor     r10, r10                    // X flag
.as_perm:
    movzx   eax, byte ptr [r13]
    cmp     al, 'r'
    jne     5f
    or      r9, 4
    inc     r13
    jmp     .as_perm
5:
    cmp     al, 'w'
    jne     6f
    or      r9, 2
    inc     r13
    jmp     .as_perm
6:
    cmp     al, 'x'
    jne     7f
    or      r9, 1
    inc     r13
    jmp     .as_perm
7:
    cmp     al, 'X'
    jne     .as_x
    mov     r10, 1
    inc     r13
    jmp     .as_perm
.as_x:
    test    r10, r10
    jz      .as_build
    mov     rax, r12                    // X: add x if directory ...
    and     rax, 0170000
    cmp     rax, 0040000
    je      .as_addx
    test    r12, 0111                   // ... or any execute bit set
    jz      .as_build
.as_addx:
    or      r9, 1
.as_build:
    xor     rcx, rcx                    // permission mask across the who fields
    test    rbx, 4
    jz      8f
    mov     rax, r9
    shl     rax, 6
    or      rcx, rax
8:
    test    rbx, 2
    jz      9f
    mov     rax, r9
    shl     rax, 3
    or      rcx, rax
9:
    test    rbx, 1
    jz      10f
    or      rcx, r9
10:
    // POSIX: with no explicit who, umask bits are not affected
    test    r11, r11
    jnz     16f
    mov     rax, [rbp + LOC_UMASK]
    not     rax
    and     rcx, rax
16:
    cmp     r8b, '+'
    jne     11f
    or      r12, rcx
    jmp     .as_sep
11:
    cmp     r8b, '-'
    jne     12f
    mov     rax, rcx
    not     rax
    and     r12, rax
    jmp     .as_sep
12:
    cmp     r8b, '='
    jne     .as_sep
    xor     rdx, rdx                    // clear the who fields' rwx, then set
    test    rbx, 4
    jz      13f
    or      rdx, 0700
13:
    test    rbx, 2
    jz      14f
    or      rdx, 070
14:
    test    rbx, 1
    jz      15f
    or      rdx, 07
15:
    not     rdx
    and     r12, rdx
    or      r12, rcx
.as_sep:
    movzx   eax, byte ptr [r13]
    test    al, al
    jz      .as_done
    cmp     al, ','
    jne     .as_sepadv
    inc     r13
    jmp     .as_clause
.as_sepadv:
    inc     r13
    jmp     .as_sep
.as_done:
    mov     rax, r12
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

err_usage: .asciz "uolt-chmod: usage: chmod MODE file...\n"
err_mode:  .asciz "uolt-chmod: invalid mode\n"
err_pre:   .asciz "uolt-chmod: "
err_suf:   .asciz ": cannot change mode\n"
