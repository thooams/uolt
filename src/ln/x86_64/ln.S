// src/ln/ln.S - the POSIX `ln` utility.
//
// ln [-s] [-f] source [target]     link source to target
// ln [-s] [-f] source... directory link each source into the directory
//
// A hard link by default, or a symbolic link with -s. With -f, an existing
// target is removed first. If `target` is omitted, the basename of `source` in
// the current directory is used. When the final operand is an existing
// directory, each source is linked to directory/basename(source).
//
// On failure a stderr diagnostic is written and the exit status is 1. No heap
// (Principle IV): the "dir/name" path is built in a stack buffer.
//
// Called as uolt_main(argc in rdi, argv in rsi) by the per-OS entry shim.
//
// Register roles (callee-saved): r12 = operand count; r13 = &argv walk;
//   r14 = exit status; r15 = flags (bit0 = -s, bit1 = -f); rbx = scratch.
// The path buffer is at [rbp - PATHMAX - 56]; [rbp-48] = source index.

#include "uolt.inc"

.set STDERR,  2
.set S_IFMT,  0170000
.set S_IFDIR, 0040000
.set PATHMAX, 4096
.set LOC_IDX, -48

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
    sub     rsp, PATHMAX + 16

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

    cmp     r12, 1
    je      .implicit                   // single operand -> basename in cwd

    // Two or more operands: if the last is a directory, link into it.
    mov     rdi, [r13 + r12*8 - 8]
    call    uolt_statmode
    test    rax, rax
    js      .explicit
    and     rax, S_IFMT
    cmp     rax, S_IFDIR
    je      .into_dir

.explicit:
    cmp     r12, 2
    jne     .usage
    mov     rbx, [r13]                  // source
    mov     rsi, [r13 + 8]              // target
    call    do_link
    jmp     .fin

.implicit:
    mov     rbx, [r13]                  // source
    mov     rsi, rbx                    // target = basename(source)
    xor     rcx, rcx
.bl:
    movzx   eax, byte ptr [rbx + rcx]
    test    al, al
    jz      .bldone
    cmp     al, '/'
    jne     4f
    lea     rsi, [rbx + rcx + 1]
4:
    inc     rcx
    jmp     .bl
.bldone:
    call    do_link
    jmp     .fin

.into_dir:
    // last operand is a directory; link each earlier source into it
    mov     qword ptr [rbp + LOC_IDX], 0
.id_loop:
    mov     rcx, [rbp + LOC_IDX]
    mov     rax, r12
    dec     rax                         // number of sources
    cmp     rcx, rax
    jae     .fin
    mov     rbx, [r13 + rcx*8]          // source
    // build "dir/basename(src)" in the buffer
    lea     rdi, [rbp - PATHMAX - 56]
    mov     rsi, [r13 + r12*8 - 8]      // directory
    call    .copy_str                   // -> rax = dir length
    lea     rdi, [rbp - PATHMAX - 56 + rax]
    mov     byte ptr [rdi], '/'
    inc     rdi
    mov     rdx, rbx                    // basename of src
    mov     rsi, rbx
.id_bn:
    movzx   eax, byte ptr [rdx]
    test    al, al
    jz      .id_bnd
    cmp     al, '/'
    jne     5f
    lea     rsi, [rdx + 1]
5:
    inc     rdx
    jmp     .id_bn
.id_bnd:
    mov     rax, rsi                    // append basename at rdi
6:
    mov     cl, [rax]
    mov     [rdi], cl
    test    cl, cl
    jz      7f
    inc     rax
    inc     rdi
    jmp     6b
7:
    lea     rsi, [rbp - PATHMAX - 56]   // target path
    call    do_link
    mov     rcx, [rbp + LOC_IDX]
    inc     rcx
    mov     [rbp + LOC_IDX], rcx
    jmp     .id_loop

.fin:
    mov     eax, r14d
    jmp     .ret
.usage:
    lea     rdi, [rip + err_usage]
    call    err_puts
    mov     eax, 1
.ret:
    add     rsp, PATHMAX + 16
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

// do_link(rbx = source, rsi = target): create the link honoring -s/-f. On
// failure sets the exit status and diagnoses. Preserves rbx, r12, r13, r14, r15.
do_link:
    push    r12
    mov     r12, rsi                    // target
    test    r15, 2                      // -f: remove an existing target first
    jz      .dl_nf
    mov     rdi, r12
    call    uolt_unlink                 // ignore result
.dl_nf:
    test    r15, 1                      // -s?
    jz      .dl_hard
    mov     rdi, rbx
    mov     rsi, r12
    call    uolt_symlink
    jmp     .dl_chk
.dl_hard:
    mov     rdi, rbx
    mov     rsi, r12
    call    uolt_link
.dl_chk:
    test    rax, rax
    jns     .dl_ret
    mov     r14, 1
    lea     rdi, [rip + err_pre]
    call    err_puts
    mov     rdi, r12
    call    err_puts
    lea     rdi, [rip + err_suf]
    call    err_puts
.dl_ret:
    pop     r12
    ret

// .copy_str(rdi = dst, rsi = src ASCIZ) -> rax = length copied.
.copy_str:
    xor     rax, rax
1:
    mov     cl, [rsi + rax]
    mov     [rdi + rax], cl
    test    cl, cl
    jz      2f
    inc     rax
    jmp     1b
2:
    ret

err_puts:
    mov     r8, rdi
    call    uolt_strlen
    mov     rdx, rax
    mov     rsi, r8
    mov     rdi, STDERR
    jmp     uolt_write

err_usage: .asciz "uolt-ln: usage: ln [-s] [-f] source... [target]\n"
err_pre:   .asciz "uolt-ln: "
err_suf:   .asciz ": cannot create link\n"
