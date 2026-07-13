// src/chmod/chmod.S - the POSIX `chmod` utility (octal mode form).
//
// chmod mode file...: set the permission bits of each file to `mode`, an octal
// number (e.g. 755, 0644). Symbolic modes (u+x, go-w, a=r, ...) are out of scope
// in v1: the relative +/- forms need the file's current mode (a stat), which is
// not yet available.
//
// A file that cannot be changed yields a stderr diagnostic and sets the exit
// status to 1, without stopping the remaining operands. No heap (Principle IV).
//
// Called as uolt_main(argc in rdi, argv in rsi) by the per-OS entry shim.
//
// Register roles (callee-saved): r12 = remaining file count, r13 = &argv walk,
//   r14 = exit status, r15 = parsed mode, rbx = current path.

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
    dec     r12                 // operand count
    lea     r13, [rsi + 8]

    xor     r14, r14

    // need at least a mode and one file
    cmp     r12, 2
    jl      .usage

    // parse the octal mode (first operand)
    mov     rbx, [r13]
    xor     r15, r15            // mode
    xor     rcx, rcx            // digit-seen flag
.pm:
    movzx   rax, byte ptr [rbx]
    test    al, al
    jz      .pm_done
    sub     al, '0'
    cmp     al, 7
    ja      .bad_mode           // not an octal digit -> symbolic (unsupported)
    shl     r15, 3              // mode = mode*8 + digit
    movzx   rax, al
    add     r15, rax
    mov     rcx, 1
    inc     rbx
    jmp     .pm
.pm_done:
    test    rcx, rcx
    jz      .bad_mode           // empty mode

    add     r13, 8              // advance past the mode operand
    dec     r12

.loop:
    test    r12, r12
    jz      .fin
    mov     rbx, [r13]
    mov     rdi, rbx
    mov     rsi, r15
    call    uolt_chmod
    test    rax, rax
    jns     .next
    mov     r14, 1
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
    mov     eax, r14d
    jmp     .ret
.bad_mode:
    lea     rdi, [rip + err_mode]
    call    err_puts
    mov     eax, 1
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

err_usage: .asciz "uolt-chmod: usage: chmod octal-mode file...\n"
err_mode:  .asciz "uolt-chmod: invalid octal mode (symbolic modes unsupported in v1)\n"
err_pre:   .asciz "uolt-chmod: "
err_suf:   .asciz ": cannot change mode\n"
