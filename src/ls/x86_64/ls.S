// src/ls/ls.S - the `ls` utility (one entry per line).
//
// ls [-a] [-1] [operand...]: list the entries of each directory operand (one
// name per line), or print the name of each file operand. With no operand, the
// current directory is listed. -a includes entries whose name starts with '.'
// (including "." and ".."); -1 is accepted and is the default (one per line).
//
// Entries are NOT sorted: sorting an unbounded set of names has no bounded,
// heap-free form, so v1 lists them in directory order (Principle IV). The
// differential test compares the set of names, not the order. Column output and
// -l are out of scope in v1.
//
// A directory is detected without stat by opening with O_DIRECTORY: that fails
// with ENOTDIR on a regular file (so "print its name") and ENOENT on a missing
// path (a diagnostic). Data flows through one 32 KB stack buffer (no heap).
//
// Called as uolt_main(argc in rdi, argv in rsi) by the per-OS entry shim.
//
// uolt_main register roles (callee-saved): r12 = operand count, r13 = &argv walk,
//   r14 = exit status, r15 = buffer base, rbx = current operand.
//   Stack local [rbp-48] = show-hidden (-a) flag.

#include "uolt.inc"

.set STDOUT,   1
.set STDERR,   2
.set ENOTDIR,  20
.set BUFSZ,    32768

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
    sub     rsp, BUFSZ + 16
    mov     r15, rsp
    xor     r14, r14
    mov     qword ptr [rbp - 48], 0     // -a flag

    mov     r12, rdi
    dec     r12
    lea     r13, [rsi + 8]

.opt:
    test    r12, r12
    jz      .after
    mov     rbx, [r13]
    cmp     byte ptr [rbx], '-'
    jne     .after
    cmp     byte ptr [rbx + 1], 0
    je      .after
    cmp     byte ptr [rbx + 1], '-'
    je      .ddash
    lea     rdi, [rbx + 1]          // validate letters are a/1
    mov     rax, rdi
.vl:
    movzx   ecx, byte ptr [rdi]
    test    cl, cl
    jz      .apply
    cmp     cl, 'a'
    je      1f
    cmp     cl, '1'
    je      1f
    jmp     .after                  // unknown -> operand
1:
    inc     rdi
    jmp     .vl
.apply:
    lea     rdi, [rbx + 1]
.apl:
    movzx   ecx, byte ptr [rdi]
    test    cl, cl
    jz      .apd
    cmp     cl, 'a'
    jne     2f
    mov     qword ptr [rbp - 48], 1
2:
    inc     rdi
    jmp     .apl
.apd:
    add     r13, 8
    dec     r12
    jmp     .opt
.ddash:
    cmp     byte ptr [rbx + 2], 0
    jne     .after
    add     r13, 8
    dec     r12
.after:
    test    r12, r12
    jnz     .oploop
    lea     rbx, [rip + dot]        // no operand -> "."
    call    list_one
    jmp     .fin
.oploop:
    test    r12, r12
    jz      .fin
    mov     rbx, [r13]
    call    list_one
    add     r13, 8
    dec     r12
    jmp     .oploop

.fin:
    mov     eax, r14d
    add     rsp, BUFSZ + 16
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

// list_one(rbx = path): list a directory's entries, or print a file's name.
//   uses r12 = fd, r13 = current batch length (both saved), r8 = first-read flag,
//   r9 = position in the batch.
list_one:
    push    r12
    push    r13
    mov     rdi, rbx
    call    uolt_opendir
    test    rax, rax
    js      .lo_not_dir             // ENOTDIR (a file), ENOENT, or another error
    mov     r12, rax                // fd
.lo_read:
    mov     rdi, r12
    mov     rsi, r15
    mov     rdx, BUFSZ
    call    uolt_getdents
    test    rax, rax
    jz      .lo_done                // end of directory
    js      .lo_readerr
    mov     r13, rax                // batch length
    xor     r9, r9
.lo_ent:
    cmp     r9, r13
    jae     .lo_read
    lea     rsi, [r15 + r9 + DIRENT_NAME_OFF]   // entry name
    cmp     qword ptr [rbp - 48], 0
    jne     .lo_print
    cmp     byte ptr [rsi], '.'
    je      .lo_next                // hidden and -a not set
.lo_print:
    mov     rdi, rsi
    call    put_name
.lo_next:
    movzx   rax, word ptr [r15 + r9 + DIRENT_RECLEN_OFF]
    test    rax, rax
    jz      .lo_read                // reclen 0 would loop forever: bail to next read
    add     r9, rax
    jmp     .lo_ent
.lo_not_dir:
    // opendir failed: ENOTDIR means "it is a file", so print its name; anything
    // else (ENOENT, EACCES, ...) is a real access error.
    cmp     rax, -ENOTDIR
    jne     .lo_diag
    mov     rdi, rbx
    call    put_name                // print the operand path
    jmp     .lo_ret
.lo_done:
    mov     rdi, r12
    call    uolt_close
    jmp     .lo_ret
.lo_readerr:
    mov     rdi, r12
    call    uolt_close
.lo_diag:
    mov     r14, 1
    lea     rdi, [rip + err_pre]
    call    err_puts
    mov     rdi, rbx
    call    err_puts
    lea     rdi, [rip + err_suf]
    call    err_puts
.lo_ret:
    pop     r13
    pop     r12
    ret

// put_name(rdi = ASCIZ name): write the name and a newline to stdout.
// Preserves r8/r9/r12/r13/r15 (uses r10 to hold the name across strlen/write).
put_name:
    mov     r10, rdi
    call    uolt_strlen
    mov     rdx, rax
    mov     rsi, r10
    mov     rdi, STDOUT
    call    uolt_write
    mov     rdi, STDOUT
    lea     rsi, [rip + nl_char]
    mov     rdx, 1
    call    uolt_write
    ret

err_puts:
    mov     r10, rdi
    call    uolt_strlen
    mov     rdx, rax
    mov     rsi, r10
    mov     rdi, STDERR
    jmp     uolt_write

dot:       .asciz "."
nl_char:   .byte  0x0a
err_pre:   .asciz "uolt-ls: "
err_suf:   .asciz ": cannot access\n"
