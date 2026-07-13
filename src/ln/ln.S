// src/ln/ln.S - the POSIX `ln` utility (single-target form).
//
// ln [-s] [-f] source [target]: create a link named `target` to `source` - a
// hard link by default, or a symbolic link with -s. With -f, an existing target
// is removed first. If `target` is omitted, the basename of `source` in the
// current directory is used. Linking more than one source into a directory is
// out of scope in v1 (that needs a directory check); one or two operands only.
//
// On failure a stderr diagnostic is written and the exit status is 1. No heap
// (Principle IV): the implicit target is the basename tail of the source string.
//
// Called as uolt_main(argc in rdi, argv in rsi) by the per-OS entry shim.
//
// Register roles (callee-saved): r12 = operand count, then the target pointer;
//   r13 = &argv walk; r14 = exit status; r15 = flags (bit0 = -s, bit1 = -f);
//   rbx = source pointer.

#include "uolt.inc"

.set STDERR, 2

.text
.globl uolt_main
uolt_main:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    mov     r12, rdi
    dec     r12
    lea     r13, [rsi + 8]
    xor     r14, r14
    xor     r15, r15

.opt:
    test    r12, r12
    jz      .after
    mov     rbx, [r13]
    cmp     byte ptr [rbx], '-'
    jne     .after
    cmp     byte ptr [rbx + 1], 0
    je      .after
    cmp     byte ptr [rbx + 1], '-'
    je      .maybe_ddash
    lea     rsi, [rbx + 1]              // validate letters are s/f
    mov     rdi, rsi
.v:
    movzx   eax, byte ptr [rdi]
    test    al, al
    jz      .apply
    cmp     al, 's'
    je      1f
    cmp     al, 'f'
    je      1f
    jmp     .after                      // unknown -> treat as an operand
1:
    inc     rdi
    jmp     .v
.apply:
    lea     rdi, [rbx + 1]
.a:
    movzx   eax, byte ptr [rdi]
    test    al, al
    jz      .adone
    cmp     al, 's'
    jne     2f
    or      r15, 1
2:
    cmp     al, 'f'
    jne     3f
    or      r15, 2
3:
    inc     rdi
    jmp     .a
.adone:
    add     r13, 8
    dec     r12
    jmp     .opt
.maybe_ddash:
    cmp     byte ptr [rbx + 2], 0
    jne     .after
    add     r13, 8
    dec     r12
.after:
    test    r12, r12
    jz      .usage
    cmp     r12, 2
    ja      .usage                      // > 2 operands unsupported in v1

    mov     rbx, [r13]                  // source
    cmp     r12, 2
    je      .have_target
    // implicit target = basename(source)
    mov     rsi, rbx
    xor     rcx, rcx
.bl:
    movzx   eax, byte ptr [rbx + rcx]
    test    al, al
    jz      .bldone
    cmp     al, '/'
    jne     4f
    lea     rsi, [rbx + rcx + 1]        // after this slash
4:
    inc     rcx
    jmp     .bl
.bldone:
    jmp     .do
.have_target:
    mov     rsi, [r13 + 8]
.do:
    mov     r12, rsi                    // target (count no longer needed)

    test    r15, 2                      // -f: remove an existing target first
    jz      .nf
    mov     rdi, r12
    call    uolt_unlink                 // ignore result
.nf:
    test    r15, 1                      // -s?
    jz      .hard
    mov     rdi, rbx                    // symlink(source, target)
    mov     rsi, r12
    call    uolt_symlink
    jmp     .chk
.hard:
    mov     rdi, rbx                    // link(source, target)
    mov     rsi, r12
    call    uolt_link
.chk:
    test    rax, rax
    jns     .fin
    mov     r14, 1
    lea     rdi, [rip + err_pre]
    call    err_puts
    mov     rdi, r12
    call    err_puts
    lea     rdi, [rip + err_suf]
    call    err_puts

.fin:
    mov     eax, r14d
    jmp     .ret
.usage:
    lea     rdi, [rip + err_usage]
    call    err_puts
    mov     eax, 1
.ret:
    pop     r15
    pop     r14
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

err_usage: .asciz "uolt-ln: usage: ln [-s] [-f] source [target]\n"
err_pre:   .asciz "uolt-ln: "
err_suf:   .asciz ": cannot create link\n"
