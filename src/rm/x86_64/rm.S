// src/rm/rm.S - the POSIX `rm` utility.
//
// rm [-f] [-r|-R] file...: remove files, and with -r/-R remove directory trees.
// With -f, non-existent operands are ignored and an empty operand list is a
// success. Without -r a directory operand is an error.
//
// Recursive removal uses the directory-read primitives (opendir/getdents) added
// with ls. rm_tree removes one entry at a time and re-opens the directory each
// pass, so no read position is held across the recursion: a single directory
// buffer and a single path buffer are reused at every level (no heap,
// Principle IV). The path buffer is grown by appending "/name" and truncated on
// return; depth is bounded by the process stack.
//
// A failure (other than a missing file under -f) writes a stderr diagnostic and
// sets the exit status to 1, without stopping the remaining operands.
//
// Called as uolt_main(argc in rdi, argv in rsi) by the per-OS entry shim.
//
// uolt_main register roles: r12 = operand count, r14 = exit status, r15 = path
//   buffer, r13 = directory buffer, rbx = scratch. Stack locals: [rbp-48] = &argv
//   walk, [rbp-56] = flags (bit0 = -f, bit1 = -r).

#include "uolt.inc"

.set STDERR,   2
.set ENOENT,   2
.set ENOTDIR,  20
.set PATHMAX,  4096
.set DBUFSZ,   32768

.set LOC_ARGV,  -48
.set LOC_FLAGS, -56

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
    sub     rsp, PATHMAX + DBUFSZ + 16
    mov     r15, rsp                    // path buffer
    lea     r13, [rsp + PATHMAX]        // directory buffer
    xor     r14, r14
    mov     qword ptr [rbp + LOC_FLAGS], 0

    mov     r12, rdi
    dec     r12
    lea     rbx, [rsi + 8]              // &argv walk (into LOC_ARGV after opts)

.opt:
    test    r12, r12
    jz      .after
    mov     rax, [rbx]
    cmp     byte ptr [rax], '-'
    jne     .after
    cmp     byte ptr [rax + 1], 0
    je      .after
    cmp     byte ptr [rax + 1], '-'
    je      .ddash
    lea     rdi, [rax + 1]              // validate letters f/r/R
    mov     rsi, rdi
.v:
    movzx   ecx, byte ptr [rdi]
    test    cl, cl
    jz      .apply
    cmp     cl, 'f'
    je      1f
    cmp     cl, 'r'
    je      1f
    cmp     cl, 'R'
    je      1f
    jmp     .after
1:
    inc     rdi
    jmp     .v
.apply:
    lea     rdi, [rsi]
.ap:
    movzx   ecx, byte ptr [rdi]
    test    cl, cl
    jz      .apd
    cmp     cl, 'f'
    jne     2f
    or      qword ptr [rbp + LOC_FLAGS], 1
2:
    cmp     cl, 'r'
    je      3f
    cmp     cl, 'R'
    jne     4f
3:
    or      qword ptr [rbp + LOC_FLAGS], 2
4:
    inc     rdi
    jmp     .ap
.apd:
    add     rbx, 8
    dec     r12
    jmp     .opt
.ddash:
    cmp     byte ptr [rax + 2], 0
    jne     .after
    add     rbx, 8
    dec     r12
.after:
    mov     [rbp + LOC_ARGV], rbx
    test    r12, r12
    jnz     .loop
    // no operands: -f -> success, else usage error
    test    qword ptr [rbp + LOC_FLAGS], 1
    jnz     .fin
    jmp     .usage

.loop:
    test    r12, r12
    jz      .fin
    mov     rbx, [rbp + LOC_ARGV]
    mov     rbx, [rbx]                  // current path
    test    qword ptr [rbp + LOC_FLAGS], 2
    jnz     .recursive
    // plain file removal
    mov     rdi, rbx
    call    uolt_unlink
    test    rax, rax
    jns     .next
    cmp     rax, -ENOENT
    jne     .diag
    test    qword ptr [rbp + LOC_FLAGS], 1
    jnz     .next                       // -f + ENOENT -> ignore
    jmp     .diag

.recursive:
    // copy the operand into the path buffer, then walk it
    mov     rdi, r15
    mov     rsi, rbx
    call    .copy_str                   // -> rax = length
    mov     rdi, rax
    call    rm_tree

.next:
    mov     rax, [rbp + LOC_ARGV]
    add     rax, 8
    mov     [rbp + LOC_ARGV], rax
    dec     r12
    jmp     .loop

.diag:
    mov     r14, 1
    mov     rdi, rbx
    call    .diag_path
    jmp     .next

.fin:
    mov     eax, r14d
    jmp     .ret
.usage:
    lea     rdi, [rip + err_usage]
    call    err_puts
    mov     eax, 1
.ret:
    add     rsp, PATHMAX + DBUFSZ + 16
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

// rm_tree(rdi = path length in the path buffer r15): remove the tree rooted at
// the path. Reopens the directory each pass, so the shared r13 buffer and r15
// path buffer are safe across the recursion. Preserves rbx (= this level's
// length).
rm_tree:
    push    rbx
    mov     rbx, rdi                    // length at this level
.rt_loop:
    mov     byte ptr [r15 + rbx], 0     // terminate the path here
    mov     rdi, r15
    call    uolt_opendir
    test    rax, rax
    js      .rt_notdir
    mov     r8, rax                     // dir fd
    mov     rdi, r8                     // read one batch
    mov     rsi, r13
    mov     rdx, DBUFSZ
    call    uolt_getdents
    mov     r9, rax                     // bytes (survives close)
    mov     rdi, r8
    call    uolt_close
    test    r9, r9
    jle     .rt_rmdir                   // no entries left -> remove the dir itself
    // find the first entry that is not "." or ".."
    xor     rcx, rcx
.rt_scan:
    cmp     rcx, r9
    jae     .rt_rmdir
    lea     rsi, [r13 + rcx + DIRENT_NAME_OFF]
    cmp     byte ptr [rsi], '.'
    jne     .rt_found
    cmp     byte ptr [rsi + 1], 0
    je      .rt_skip
    cmp     byte ptr [rsi + 1], '.'
    jne     .rt_found
    cmp     byte ptr [rsi + 2], 0
    je      .rt_skip
    jmp     .rt_found
.rt_skip:
    movzx   rax, word ptr [r13 + rcx + DIRENT_RECLEN_OFF]
    test    rax, rax
    jz      .rt_rmdir                   // reclen 0 guard
    add     rcx, rax
    jmp     .rt_scan
.rt_found:
    // append "/name" to the path at [r15 + rbx]
    mov     byte ptr [r15 + rbx], '/'
    lea     rdi, [r15 + rbx + 1]
.rt_cpy:
    mov     al, [rsi]
    mov     [rdi], al
    test    al, al
    jz      .rt_cpydone
    inc     rsi
    inc     rdi
    jmp     .rt_cpy
.rt_cpydone:
    sub     rdi, r15                    // rdi = &NUL - base = new length
    call    rm_tree                     // recurse (preserves rbx)
    jmp     .rt_loop                    // reopen and take the next entry
.rt_notdir:
    cmp     rax, -ENOTDIR
    jne     .rt_patherr
    mov     rdi, r15                    // a file: unlink it
    call    uolt_unlink
    test    rax, rax
    js      .rt_patherr_e
    jmp     .rt_ok
.rt_rmdir:
    mov     rdi, r15
    call    uolt_rmdir
    test    rax, rax
    js      .rt_patherr_e
.rt_ok:
    pop     rbx
    ret
.rt_patherr:
    // opendir error other than ENOTDIR (e.g. ENOENT): under -f ignore ENOENT
    cmp     rax, -ENOENT
    jne     .rt_patherr_e
    test    qword ptr [rbp + LOC_FLAGS], 1
    jnz     .rt_ok
.rt_patherr_e:
    mov     r14, 1
    mov     rdi, r15
    call    .diag_path
    pop     rbx
    ret

// .copy_str(rdi = dst, rsi = src ASCIZ) -> rax = length copied (excluding NUL).
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

// .diag_path(rdi = path): "uolt-rm: <path>: cannot remove" to stderr.
.diag_path:
    mov     r9, rdi
    lea     rdi, [rip + err_pre]
    call    err_puts
    mov     rdi, r9
    call    err_puts
    lea     rdi, [rip + err_suf]
    call    err_puts
    ret

err_puts:
    mov     r10, rdi
    call    uolt_strlen
    mov     rdx, rax
    mov     rsi, r10
    mov     rdi, STDERR
    jmp     uolt_write

err_usage: .asciz "uolt-rm: usage: rm [-f] [-r] file...\n"
err_pre:   .asciz "uolt-rm: "
err_suf:   .asciz ": cannot remove\n"
