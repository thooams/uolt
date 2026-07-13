// src/cp/cp.S - the POSIX `cp` utility (two-operand file form).
//
// cp source target: copy the contents of `source` to `target`, creating or
// truncating the target. Data is streamed through one 64 KB stack buffer (no
// heap, Principle IV). Copying into a directory (cp src... dir) and recursive
// copies (-r) are out of scope in v1 (both need stat / directory reading);
// permission bits are not preserved (the target gets 0666 masked by the umask,
// which matches a default-mode source).
//
// A failure yields a stderr diagnostic and exit 1.
//
// Called as uolt_main(argc in rdi, argv in rsi) by the per-OS entry shim.
//
// Register roles (callee-saved): r12 = source fd, rbx = target fd,
//   r13 = &argv (paths), r14 = exit status, r15 = buffer base.

#include "uolt.inc"

.set STDERR,   2
.set O_RDONLY, 0
.set MODE,     0666
.set BUFSZ,    65536

.text
.globl uolt_main
uolt_main:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, BUFSZ
    mov     r15, rsp

    mov     r12, rdi
    dec     r12
    lea     r13, [rsi + 8]
    xor     r14, r14

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
    jne     .usage

    // open source
    mov     rdi, [r13]
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    call    uolt_open
    test    rax, rax
    js      .src_err
    mov     r12, rax            // source fd

    // open/create/truncate target
    mov     rdi, [r13 + 8]
    mov     rsi, MODE
    call    uolt_opendst
    test    rax, rax
    js      .dst_err
    mov     rbx, rax            // target fd

    // copy loop
.cpy:
    mov     rdi, r12
    mov     rsi, r15
    mov     rdx, BUFSZ
    call    uolt_read
    test    rax, rax
    jz      .cdone
    js      .copy_err
    mov     r8, rax             // remaining
    mov     r9, r15             // ptr
.wr:
    mov     rdi, rbx
    mov     rsi, r9
    mov     rdx, r8
    call    uolt_write
    test    rax, rax
    js      .copy_err
    add     r9, rax
    sub     r8, rax
    jnz     .wr
    jmp     .cpy
.cdone:
    mov     rdi, r12
    call    uolt_close
    mov     rdi, rbx
    call    uolt_close
    jmp     .fin

.copy_err:
    mov     rdi, r12
    call    uolt_close
    mov     rdi, rbx
    call    uolt_close
    lea     rsi, [r13 + 8]      // report the target
    call    .diag
    jmp     .fin
.src_err:
    lea     rsi, [r13]          // report the source
    call    .diag
    jmp     .fin
.dst_err:
    mov     rdi, r12            // close the already-open source
    call    uolt_close
    lea     rsi, [r13 + 8]
    call    .diag

.fin:
    mov     eax, r14d
    add     rsp, BUFSZ
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret
.usage:
    lea     rdi, [rip + err_usage]
    call    err_puts
    mov     eax, 1
    add     rsp, BUFSZ
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

// .diag(rsi = &(char* path)): "uolt-cp: <path>: ..." to stderr, status 1.
.diag:
    mov     r14, 1
    push    rsi
    lea     rdi, [rip + err_pre]
    call    err_puts
    pop     rsi
    mov     rdi, [rsi]          // the path string
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

err_usage: .asciz "uolt-cp: usage: cp source target\n"
err_pre:   .asciz "uolt-cp: "
err_suf:   .asciz ": cannot copy\n"
