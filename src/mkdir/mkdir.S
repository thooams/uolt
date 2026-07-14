// src/mkdir/mkdir.S - the POSIX `mkdir` utility.
//
// mkdir [-p] [-m MODE] dir...: create each named directory. With -p, missing
// parent directories are created too and an already-existing target is not an
// error. Without -m the mode is 0777 and the kernel applies the process umask
// (the usual 0755 result); with -m the target is created and then chmod'd to the
// exact octal MODE (umask not applied), while any -p parents keep the default.
//
// A directory that cannot be created yields a stderr diagnostic and sets the
// exit status to 1, without stopping the remaining operands. No heap
// (Principle IV): the -p walk edits the operand string in place (NUL-terminating
// each prefix, then restoring the slash).
//
// Called as uolt_main(argc in rdi, argv in rsi) by the per-OS entry shim.
//
// Register roles (callee-saved):
//   r12 = remaining operand count, r13 = &argv walk, r14 = exit status,
//   r15 = -p flag, rbx = current path. Stack: [-48] = -m mode, [-56] = -m flag.

#include "uolt.inc"

.set STDERR, 2
.set MODE,   0777               // umask is applied by the kernel
.set EEXIST, 17

.set LOC_MODE, -48
.set LOC_HASM, -56

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
    sub     rsp, 16

    mov     r12, rdi
    dec     r12
    lea     r13, [rsi + 8]
    xor     r14, r14
    xor     r15, r15            // -p flag
    mov     qword ptr [rbp + LOC_MODE], MODE
    mov     qword ptr [rbp + LOC_HASM], 0

.opt:
    test    r12, r12
    jz      .after
    mov     rbx, [r13]
    cmp     byte ptr [rbx], '-'
    jne     .after
    cmp     byte ptr [rbx + 1], 0
    je      .after              // "-" -> a directory named "-"
    cmp     byte ptr [rbx + 1], 'p'
    jne     1f
    cmp     byte ptr [rbx + 2], 0
    jne     1f
    mov     r15, 1              // -p
    add     r13, 8
    dec     r12
    jmp     .opt
1:
    cmp     byte ptr [rbx + 1], 'm'
    jne     2f
    lea     rdi, [rbx + 2]      // "-mMODE" attached, or "-m" then next arg
    cmp     byte ptr [rdi], 0
    jne     .have_mode
    add     r13, 8
    dec     r12
    jz      .usage
    mov     rdi, [r13]
.have_mode:
    call    parse_octal
    jc      .usage
    mov     [rbp + LOC_MODE], rax
    mov     qword ptr [rbp + LOC_HASM], 1
    add     r13, 8
    dec     r12
    jmp     .opt
2:
    cmp     byte ptr [rbx + 1], '-'
    jne     .after
    cmp     byte ptr [rbx + 2], 0
    jne     .after
    add     r13, 8              // "--"
    dec     r12
.after:
    test    r12, r12
    jz      .usage

.loop:
    test    r12, r12
    jz      .fin
    mov     rbx, [r13]
    test    r15, r15
    jnz     .p_mode
    // plain mkdir
    mov     rdi, rbx
    mov     rsi, [rbp + LOC_MODE]
    call    uolt_mkdir
    test    rax, rax
    js      1f
    call    apply_mode          // -m: chmod to the exact mode
    jmp     .next
1:
    call    .diag               // rbx = failing path
    jmp     .next
.p_mode:
    call    mkdir_p
.next:
    add     r13, 8
    dec     r12
    jmp     .loop

.fin:
    mov     eax, r14d
    jmp     .ret
.usage:
    lea     rdi, [rip + err_usage]
    call    err_puts
    mov     eax, 1
.ret:
    add     rsp, 16
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

// mkdir_p(rbx = path): create every prefix directory, ignoring EEXIST, then the
// full path. Uses r12 as the walk index (saved: the caller's operand count).
mkdir_p:
    push    r12
    xor     r12, r12
.mp_loop:
    movzx   rax, byte ptr [rbx + r12]
    test    al, al
    jz      .mp_final
    cmp     al, '/'
    jne     .mp_next
    test    r12, r12
    jz      .mp_next            // leading slash: no empty prefix
    cmp     byte ptr [rbx + r12 - 1], '/'
    je      .mp_next            // collapse repeated slashes
    mov     byte ptr [rbx + r12], 0     // terminate the prefix
    mov     rdi, rbx
    mov     rsi, MODE
    call    uolt_mkdir          // ignore result (EEXIST is fine; real errors surface at the end)
    mov     byte ptr [rbx + r12], '/'   // restore
.mp_next:
    inc     r12
    jmp     .mp_loop
.mp_final:
    mov     rdi, rbx
    mov     rsi, [rbp + LOC_MODE]
    call    uolt_mkdir
    test    rax, rax
    jns     .mp_created
    cmp     rax, -EEXIST
    je      .mp_done            // already exists -> ok under -p (mode unchanged)
    pop     r12
    jmp     .diag               // tail into the diagnostic (which returns)
.mp_created:
    pop     r12
    call    apply_mode          // -m applies only to a freshly created target
    ret
.mp_done:
    pop     r12
    ret

// apply_mode(rbx = path): with -m, chmod the path to the exact mode (best effort).
apply_mode:
    cmp     qword ptr [rbp + LOC_HASM], 0
    je      1f
    mov     rdi, rbx
    mov     rsi, [rbp + LOC_MODE]
    call    uolt_chmod
1:
    ret

// parse_octal(rdi = ASCIZ) -> rax = value; CF set on error (empty or non-octal).
parse_octal:
    xor     rax, rax
    xor     r9, r9
    movzx   ecx, byte ptr [rdi]
    test    cl, cl
    jz      .po_err
.po:
    movzx   ecx, byte ptr [rdi]
    test    cl, cl
    jz      .po_done
    sub     cl, '0'
    cmp     cl, 7
    ja      .po_err
    shl     rax, 3
    movzx   rcx, cl
    add     rax, rcx
    mov     r9, 1
    inc     rdi
    jmp     .po
.po_done:
    test    r9, r9
    jz      .po_err
    clc
    ret
.po_err:
    stc
    ret

// .diag(rbx = path): "uolt-mkdir: <path>: cannot create" to stderr, status 1.
.diag:
    mov     r14, 1
    lea     rdi, [rip + err_pre]
    call    err_puts
    mov     rdi, rbx
    call    err_puts
    lea     rdi, [rip + err_suf]
    call    err_puts
    ret

err_puts:
    mov     r8, rdi
    call    uolt_strlen
    mov     rdx, rax
    mov     rsi, r8
    mov     rdi, STDERR
    jmp     uolt_write

err_usage: .asciz "uolt-mkdir: usage: mkdir [-p] [-m MODE] dir...\n"
err_pre:   .asciz "uolt-mkdir: "
err_suf:   .asciz ": cannot create directory\n"
