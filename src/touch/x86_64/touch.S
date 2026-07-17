// src/touch/touch.S - the POSIX `touch` utility.
//
// touch [-c] [-a] [-m] file...: set each file's access and modification times to
// the current time, creating an empty file if it does not exist. With -c, a
// missing file is not created (and is not an error). -a and -m are accepted and
// ignored: this version always updates both times to now (the common case);
// -r / -t (reference / explicit time) are out of scope in v1.
//
// For each file: create it (open O_WRONLY|O_CREAT then close) unless -c, then
// call utimes(path, NULL) to stamp both times to now. Under -c a missing file's
// ENOENT is ignored. A real failure yields a stderr diagnostic and exit 1,
// without stopping the remaining operands. No heap (Principle IV).
//
// Called as uolt_main(argc in rdi, argv in rsi) by the per-OS entry shim.
//
// Register roles (callee-saved): r12 = operand count, r13 = &argv walk,
//   r14 = exit status, r15 = -c (no-create) flag, rbx = current path.

#include "uolt.inc"

.set STDERR, 2
.set MODE,   0666               // umask applied by the kernel
.set ENOENT, 2

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
    xor     r15, r15            // -c flag

.opt:
    test    r12, r12
    jz      .after
    mov     rbx, [r13]
    cmp     byte ptr [rbx], '-'
    jne     .after
    cmp     byte ptr [rbx + 1], 0
    je      .after              // "-" -> a file named "-"
    cmp     byte ptr [rbx + 1], '-'
    jne     .flags
    cmp     byte ptr [rbx + 2], 0
    jne     .flags
    add     r13, 8              // "--"
    dec     r12
    jmp     .after
.flags:
    lea     rsi, [rbx + 1]      // validate the option letters (c/a/m only)
    mov     rdi, rsi
.val:
    movzx   eax, byte ptr [rdi]
    test    al, al
    jz      .apply
    cmp     al, 'c'
    je      1f
    cmp     al, 'a'
    je      1f
    cmp     al, 'm'
    je      1f
    jmp     .after              // unknown letter -> treat as an operand
1:
    inc     rdi
    jmp     .val
.apply:
    mov     rdi, rsi
.ap:
    movzx   eax, byte ptr [rdi]
    test    al, al
    jz      .ap_done
    cmp     al, 'c'
    jne     2f
    mov     r15, 1              // -c: do not create
2:
    inc     rdi
    jmp     .ap
.ap_done:
    add     r13, 8
    dec     r12
    jmp     .opt

.after:
    test    r12, r12
    jz      .usage

.loop:
    test    r12, r12
    jz      .fin
    mov     rbx, [r13]

    test    r15, r15
    jnz     .stamp              // -c: skip creation
    mov     rdi, rbx            // create (or open) the file
    mov     rsi, MODE
    call    uolt_create
    test    rax, rax
    js      .diag_next          // could not create
    mov     rdi, rax
    call    uolt_close
.stamp:
    mov     rdi, rbx            // utimes(path, NULL) -> both times = now
    xor     rsi, rsi
    call    uolt_utimes
    test    rax, rax
    jns     .next
    // error: under -c a missing file is fine; anything else is a diagnostic
    cmp     rax, -ENOENT
    jne     .diag
    test    r15, r15
    jnz     .next               // -c and ENOENT -> ignore
.diag:
    mov     r14, 1
    lea     rdi, [rip + err_pre]
    call    err_puts
    mov     rdi, rbx
    call    err_puts
    lea     rdi, [rip + err_suf]
    call    err_puts
    jmp     .next
.diag_next:
    call    .do_diag
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

// .do_diag(rbx = path): shared diagnostic used by the create-failure path.
.do_diag:
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

err_usage: .asciz "uolt-touch: usage: touch [-c] file...\n"
err_pre:   .asciz "uolt-touch: "
err_suf:   .asciz ": cannot touch\n"
