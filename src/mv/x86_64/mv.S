// src/mv/mv.S - the POSIX `mv` utility.
//
// mv source target        rename source to target
// mv source... directory  move each source into the directory
//
// When the final operand is an existing directory, each source is renamed to
// "directory/basename(source)"; otherwise exactly two operands are required and
// the source is renamed to the target. The rename syscall atomically replaces an
// existing target file. Cross-device moves (rename -> EXDEV, needing copy+unlink)
// are not handled in v1.
//
// A failure yields a stderr diagnostic and exit 1. No heap (Principle IV): the
// "dir/name" path is built in a stack buffer.
//
// Called as uolt_main(argc in rdi, argv in rsi) by the per-OS entry shim.
//
// Register roles (callee-saved): r12 = operand count, r13 = &argv walk,
//   r14 = exit status, r15 = path buffer, rbx = current source.

#include "uolt.inc"

.set STDERR,  2
.set S_IFMT,  0170000
.set S_IFDIR, 0040000
.set PATHMAX, 4096

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
    mov     r15, rsp
    xor     r14, r14
    mov     qword ptr [rbp - 48], 0     // directory path (0 = not dir mode)
    mov     qword ptr [rbp - 56], 0     // source index (dir mode)

    mov     r12, rdi
    dec     r12
    lea     r13, [rsi + 8]

    // optional "--"
    test    r12, r12
    jz      .usage
    mov     rax, [r13]
    cmp     byte ptr [rax], '-'
    jne     .after
    cmp     byte ptr [rax + 1], '-'
    jne     .after
    cmp     byte ptr [rax + 2], 0
    jne     .after
    add     r13, 8
    dec     r12
.after:
    cmp     r12, 2
    jl      .usage

    // Is the last operand a directory?
    mov     rdi, [r13 + r12*8 - 8]
    call    uolt_statmode
    test    rax, rax
    js      .not_dir
    and     rax, S_IFMT
    cmp     rax, S_IFDIR
    jne     .not_dir

    // Directory target: move every earlier operand into it. The directory path
    // and the source index live in stack slots so they survive err_puts.
    mov     rax, [r13 + r12*8 - 8]
    mov     [rbp - 48], rax             // directory path
.dloop:
    mov     r9, [rbp - 56]              // source index
    mov     r8, r12
    dec     r8                          // number of sources
    cmp     r9, r8
    jae     .fin
    mov     rbx, [r13 + r9*8]           // source (rbx preserved through the build)
    // build "dir/basename(src)" in the path buffer
    mov     rsi, [rbp - 48]
    mov     rdi, r15
    call    .copy_str                   // dir -> rax = dir length
    mov     rcx, rax
    mov     byte ptr [r15 + rcx], '/'
    inc     rcx
    mov     rdx, rbx                    // basename of src (scan for last '/')
    mov     rsi, rbx
.bn:
    movzx   eax, byte ptr [rdx]
    test    al, al
    jz      .bn_done
    cmp     al, '/'
    jne     1f
    lea     rsi, [rdx + 1]
1:
    inc     rdx
    jmp     .bn
.bn_done:
    lea     rdi, [r15 + rcx]            // append basename at [r15+rcx]
    mov     rax, rsi
.ba:
    mov     cl, [rax]
    mov     [rdi], cl
    test    cl, cl
    jz      .ba_done
    inc     rax
    inc     rdi
    jmp     .ba
.ba_done:
    mov     rdi, rbx
    mov     rsi, r15
    call    uolt_rename
    test    rax, rax
    js      .diag
.dnext:
    mov     rax, [rbp - 56]
    inc     rax
    mov     [rbp - 56], rax
    jmp     .dloop

.not_dir:
    cmp     r12, 2
    jne     .usage
    mov     rbx, [r13]
    mov     rdi, [r13]
    mov     rsi, [r13 + 8]
    call    uolt_rename
    test    rax, rax
    js      .diag
    jmp     .fin

.diag:
    mov     r14, 1
    lea     rdi, [rip + err_pre]
    call    err_puts
    mov     rdi, rbx
    call    err_puts
    lea     rdi, [rip + err_suf]
    call    err_puts
    // in directory mode, continue with the remaining sources
    cmp     qword ptr [rbp - 48], 0
    je      .fin
    jmp     .dnext

.fin:
    mov     eax, r14d
    add     rsp, PATHMAX + 16
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
.usage:
    lea     rdi, [rip + err_usage]
    call    err_puts
    mov     eax, 1
    add     rsp, PATHMAX + 16
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
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

err_usage: .asciz "uolt-mv: usage: mv source... target\n"
err_pre:   .asciz "uolt-mv: "
err_suf:   .asciz ": cannot move\n"
