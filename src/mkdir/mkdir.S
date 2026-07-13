// src/mkdir/mkdir.S - the POSIX `mkdir` utility.
//
// mkdir [-p] dir...: create each named directory. With -p, missing parent
// directories are created too and an already-existing target is not an error.
// The mode passed is 0777; the kernel applies the process umask, giving the
// usual 0755 result. -m (explicit mode) is out of scope in v1.
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
//   r15 = -p flag, rbx = current path

#include "uolt.inc"

.set STDERR, 2
.set MODE,   0777               // umask is applied by the kernel
.set EEXIST, 17

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
    xor     r15, r15            // -p flag

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
    mov     rsi, MODE
    call    uolt_mkdir
    test    rax, rax
    jns     .next
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
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
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
    mov     rsi, MODE
    call    uolt_mkdir
    test    rax, rax
    jns     .mp_done
    cmp     rax, -EEXIST
    je      .mp_done            // already exists -> ok under -p
    pop     r12
    jmp     .diag               // tail into the diagnostic (which returns)
.mp_done:
    pop     r12
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

err_usage: .asciz "uolt-mkdir: usage: mkdir [-p] dir...\n"
err_pre:   .asciz "uolt-mkdir: "
err_suf:   .asciz ": cannot create directory\n"
