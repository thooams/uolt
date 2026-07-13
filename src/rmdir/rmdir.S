// src/rmdir/rmdir.S - the POSIX `rmdir` utility.
//
// rmdir [-p] dir...: remove each named empty directory. With -p, after removing
// the directory its now-empty parent directories are removed too, walking up the
// path until one is not removable (e.g. non-empty). A directory that cannot be
// removed yields a stderr diagnostic and sets the exit status to 1, without
// stopping the remaining operands.
//
// No heap (Principle IV): the -p walk shortens the operand string in place,
// terminating it at each ancestor.
//
// Called as uolt_main(argc in rdi, argv in rsi) by the per-OS entry shim.
//
// Register roles (callee-saved): r12 = operand count, r13 = &argv walk,
//   r14 = exit status, r15 = -p flag, rbx = current path.

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
    cmp     byte ptr [rbx + 1], 'p'
    jne     1f
    cmp     byte ptr [rbx + 2], 0
    jne     1f
    mov     r15, 1
    add     r13, 8
    dec     r12
    jmp     .opt
1:
    cmp     byte ptr [rbx + 1], '-'
    jne     .after
    cmp     byte ptr [rbx + 2], 0
    jne     .after
    add     r13, 8
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
    mov     rdi, rbx
    call    uolt_rmdir
    test    rax, rax
    jns     .next
    call    .diag
    jmp     .next
.p_mode:
    call    rmdir_p
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
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

// rmdir_p(rbx = path): remove the directory, then each ancestor, stopping at the
// first that cannot be removed. r12 holds the current end index (saved).
rmdir_p:
    push    r12
    mov     rdi, rbx
    call    uolt_strlen
    mov     r12, rax            // e = length
    // strip trailing slashes
.rp_trail:
    test    r12, r12
    jz      .rp_done
    cmp     byte ptr [rbx + r12 - 1], '/'
    jne     .rp_rm
    dec     r12
    jmp     .rp_trail
.rp_rm:
    mov     byte ptr [rbx + r12], 0     // terminate at e
    mov     rdi, rbx
    call    uolt_rmdir
    test    rax, rax
    js      .rp_err
    // move e back over the last component and its separating slashes -> parent
.rp_comp:
    test    r12, r12
    jz      .rp_done
    cmp     byte ptr [rbx + r12 - 1], '/'
    je      .rp_sep
    dec     r12
    jmp     .rp_comp
.rp_sep:
    test    r12, r12
    jz      .rp_done
    cmp     byte ptr [rbx + r12 - 1], '/'
    jne     .rp_rm              // parent found -> remove it
    dec     r12
    jmp     .rp_sep
.rp_err:
    pop     r12
    jmp     .diag               // report and return
.rp_done:
    pop     r12
    ret

// .diag(rbx = path): "uolt-rmdir: <path>: cannot remove" to stderr, status 1.
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

err_usage: .asciz "uolt-rmdir: usage: rmdir [-p] dir...\n"
err_pre:   .asciz "uolt-rmdir: "
err_suf:   .asciz ": cannot remove directory\n"
