// src/tee/tee.S - the POSIX `tee` utility.
//
// tee [-a] [file...]: copy standard input to standard output and to each named
// file. With -a the files are appended to instead of truncated. Data flows
// through one 64 KB stack buffer (no heap, Principle IV); each read block is
// drained to stdout and to every open output file. Up to MAXFILES files are
// supported; a file that cannot be opened yields a diagnostic and sets the exit
// status to 1 but does not stop the copy to the others.
//
// Called as uolt_main(argc in rdi, argv in rsi) by the per-OS entry shim.
//
// Register roles (callee-saved): r12 = number of open fds, r13 = fd array base,
//   r14 = exit status, r15 = buffer base, rbx = remaining operand count.
//   Stack locals: [rbp-48] = append flag, [rbp-56] = &argv walk.

#include "uolt.inc"

.set STDIN,   0
.set STDOUT,  1
.set STDERR,  2
.set MODE,    0666
.set BUFSZ,   65536
.set MAXFILES, 64

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
    sub     rsp, BUFSZ + MAXFILES*8 + 32
    mov     r15, rsp
    lea     r13, [rsp + BUFSZ]          // fd array
    xor     r14, r14
    xor     r12, r12                    // open fd count
    mov     qword ptr [rbp - 48], 0     // append flag

    mov     rbx, rdi
    dec     rbx                         // operand count
    lea     rax, [rsi + 8]
    mov     [rbp - 56], rax             // &argv walk

.opt:
    test    rbx, rbx
    jz      .open_files
    mov     rax, [rbp - 56]
    mov     rax, [rax]
    cmp     byte ptr [rax], '-'
    jne     .open_files
    cmp     byte ptr [rax + 1], 0
    je      .open_files                 // "-" is a file operand
    cmp     byte ptr [rax + 1], 'a'
    jne     1f
    cmp     byte ptr [rax + 2], 0
    jne     1f
    mov     qword ptr [rbp - 48], 1     // -a
    add     qword ptr [rbp - 56], 8
    dec     rbx
    jmp     .opt
1:
    cmp     byte ptr [rax + 1], '-'
    jne     .open_files
    cmp     byte ptr [rax + 2], 0
    jne     .open_files
    add     qword ptr [rbp - 56], 8
    dec     rbx

.open_files:
    test    rbx, rbx
    jz      .copy
    cmp     r12, MAXFILES
    jae     .copy
    mov     rax, [rbp - 56]
    mov     rdi, [rax]                  // path
    push    rdi
    mov     rsi, MODE
    cmp     qword ptr [rbp - 48], 0
    je      .of_trunc
    call    uolt_openapp
    jmp     .of_check
.of_trunc:
    call    uolt_opendst
.of_check:
    pop     rdi                         // path (for a possible diagnostic)
    test    rax, rax
    js      .of_err
    mov     [r13 + r12*8], rax          // store the fd
    inc     r12
    jmp     .of_next
.of_err:
    mov     r14, 1
    push    rdi
    lea     rdi, [rip + err_pre]
    call    err_puts
    pop     rdi
    call    err_puts
    lea     rdi, [rip + err_suf]
    call    err_puts
.of_next:
    add     qword ptr [rbp - 56], 8
    dec     rbx
    jmp     .open_files

.copy:
    mov     rdi, STDIN
    mov     rsi, r15
    mov     rdx, BUFSZ
    call    uolt_read
    test    rax, rax
    jle     .done                       // EOF (0) or error (<0)
    mov     [rbp - 64], rax             // block length
    mov     rbx, -1                     // fd index: -1 = stdout, 0.. = files
.cp_out:
    cmp     rbx, r12
    jge     .copy                       // wrote to stdout + all files: read again
    test    rbx, rbx
    js      1f
    mov     r10, [r13 + rbx*8]          // file fd
    jmp     2f
1:
    mov     r10, STDOUT
2:
    mov     r8, [rbp - 64]              // remaining bytes for this fd
    mov     r9, r15
.cp_w:
    test    r8, r8
    jz      .cp_done_fd
    mov     rdi, r10                    // fd (r10 survives the write syscall)
    mov     rsi, r9
    mov     rdx, r8
    call    uolt_write
    test    rax, rax
    js      .cp_werr
    add     r9, rax
    sub     r8, rax
    jmp     .cp_w
.cp_werr:
    mov     r14, 1
.cp_done_fd:
    inc     rbx
    jmp     .cp_out

.done:
    // close all output files
    xor     rbx, rbx
.dc:
    cmp     rbx, r12
    jae     .fin
    mov     rdi, [r13 + rbx*8]
    call    uolt_close
    inc     rbx
    jmp     .dc
.fin:
    mov     eax, r14d
    add     rsp, BUFSZ + MAXFILES*8 + 32
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

err_puts:
    mov     r10, rdi
    call    uolt_strlen
    mov     rdx, rax
    mov     rsi, r10
    mov     rdi, STDERR
    jmp     uolt_write

err_pre: .asciz "uolt-tee: "
err_suf: .asciz ": cannot open\n"
