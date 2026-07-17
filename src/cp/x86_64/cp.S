// src/cp/cp.S - the `cp` utility (file copy, plus recursive -r).
//
// cp source target        copy a file's contents to target
// cp -r source target      copy a directory tree to target
//
// Data is streamed through one 64 KB stack buffer (no heap, Principle IV). With
// -r, directories are walked recursively (opendir/getdents from ls) and
// re-created (mkdir); two path buffers - source and target - are grown in
// parallel and truncated on return. Permission bits are not preserved (files get
// 0666 masked by the umask, directories 0777 masked). When the final operand is
// an existing directory, each source is copied to dir/basename(source) (this is
// the cp src... dir form). Same-file detection is out of scope in v1.
//
// Called as uolt_main(argc in rdi, argv in rsi) by the per-OS entry shim.
//
// Global registers: r15 = base of (srcbuf[PATHMAX] dstbuf[PATHMAX] copybuf[BUFSZ]).
// Stack locals: [-48] = exit status, [-56] = -r flag.

#include "uolt.inc"

.set STDERR,   2
.set O_RDONLY, 0
.set ENOTDIR,  20
.set EEXIST,   17
.set FMODE,    0666
.set DMODE,    0777
.set BUFSZ,    65536
.set PATHMAX,  4096
.set DBUFSZ,   4096

.set LOC_STAT, -48
.set LOC_R,    -56
.set LOC_DIR,  -64
.set S_IFMT,   0170000
.set S_IFDIR,  0040000

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
    sub     rsp, 2*PATHMAX + BUFSZ + 64
    mov     r15, rsp
    mov     qword ptr [rbp + LOC_STAT], 0
    mov     qword ptr [rbp + LOC_R], 0

    mov     r12, rdi
    dec     r12
    lea     r13, [rsi + 8]

.opt:
    test    r12, r12
    jz      .usage
    mov     rax, [r13]
    cmp     byte ptr [rax], '-'
    jne     .after
    cmp     byte ptr [rax + 1], 0
    je      .after
    cmp     byte ptr [rax + 1], '-'
    je      .ddash
    // -r / -R (and combined, though only r/R meaningful)
    lea     rcx, [rax + 1]
.optf:
    movzx   edx, byte ptr [rcx]
    test    dl, dl
    jz      .optnext
    cmp     dl, 'r'
    je      1f
    cmp     dl, 'R'
    jne     .after
1:
    mov     qword ptr [rbp + LOC_R], 1
    inc     rcx
    jmp     .optf
.optnext:
    add     r13, 8
    dec     r12
    jmp     .opt
.ddash:
    cmp     byte ptr [rax + 2], 0
    jne     .after
    add     r13, 8
    dec     r12
.after:
    cmp     r12, 2
    jl      .usage

    // If the final operand is an existing directory, copy each source into it.
    mov     rdi, [r13 + r12*8 - 8]
    call    uolt_statmode
    test    rax, rax
    js      .two
    and     rax, S_IFMT
    cmp     rax, S_IFDIR
    jne     .two

    // Into-directory form: for each source, dst = dir/basename(source).
    mov     rax, [r13 + r12*8 - 8]
    mov     [rbp + LOC_DIR], rax
    xor     r14, r14                    // source index
.id_loop:
    mov     rax, r12
    dec     rax                         // number of sources
    cmp     r14, rax
    jae     .fin
    mov     rsi, [r13 + r14*8]          // source into srcbuf
    mov     rdi, r15
    call    .copy_str
    mov     rbx, rax                    // src length
    mov     rsi, [rbp + LOC_DIR]        // dir into dstbuf
    lea     rdi, [r15 + PATHMAX]
    call    .copy_str
    mov     rcx, rax
    mov     byte ptr [r15 + PATHMAX + rcx], '/'
    inc     rcx
    mov     rdx, [r13 + r14*8]          // basename of source (scan for last '/')
    mov     rsi, rdx
.id_bn:
    movzx   eax, byte ptr [rdx]
    test    al, al
    jz      .id_bndone
    cmp     al, '/'
    jne     1f
    lea     rsi, [rdx + 1]
1:
    inc     rdx
    jmp     .id_bn
.id_bndone:
    lea     rdi, [r15 + PATHMAX + rcx]  // append basename
    mov     rax, rsi
2:
    mov     dl, [rax]
    mov     [rdi], dl
    test    dl, dl
    jz      3f
    inc     rax
    inc     rdi
    jmp     2b
3:
    lea     rax, [r15 + PATHMAX]
    sub     rdi, rax                    // rdi = dst length
    cmp     qword ptr [rbp + LOC_R], 0
    jne     .id_tree
    mov     rdi, r15
    lea     rsi, [r15 + PATHMAX]
    call    copy_file
    jmp     .id_next
.id_tree:
    mov     rsi, rdi                    // dst length
    mov     rdi, rbx                    // src length
    call    copy_tree
.id_next:
    inc     r14
    jmp     .id_loop

.two:
    cmp     r12, 2
    jne     .usage
    // copy the two operands into the path buffers
    mov     rdi, r15
    mov     rsi, [r13]
    call    .copy_str                   // -> rax = src length
    mov     rbx, rax                    // src length
    lea     rdi, [r15 + PATHMAX]
    mov     rsi, [r13 + 8]
    call    .copy_str
    mov     r12, rax                    // dst length

    cmp     qword ptr [rbp + LOC_R], 0
    jne     .recursive
    // plain file copy
    mov     rdi, r15
    lea     rsi, [r15 + PATHMAX]
    call    copy_file
    jmp     .fin
.recursive:
    mov     rdi, rbx
    mov     rsi, r12
    call    copy_tree

.fin:
    mov     rax, [rbp + LOC_STAT]
    add     rsp, 2*PATHMAX + BUFSZ + 64
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
    mov     rax, 1
    add     rsp, 2*PATHMAX + BUFSZ + 64
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

// copy_tree(rdi = src length, rsi = dst length): copy the source (a file or a
// directory tree) at srcbuf to dstbuf. Preserves rbx (src len) and r13 (dst len)
// across the recursion; the per-level directory buffer + scan state live in this
// level's stack frame.
copy_tree:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi                    // src length (this level)
    mov     r13, rsi                    // dst length
    mov     byte ptr [r15 + rbx], 0
    mov     byte ptr [r15 + PATHMAX + r13], 0
    mov     rdi, r15
    call    uolt_opendir
    test    rax, rax
    js      .ct_notdir
    mov     r12, rax                    // source directory fd
    lea     rdi, [r15 + PATHMAX]        // create the target directory
    mov     rsi, DMODE
    call    uolt_mkdir                  // ignore result (EEXIST ok)
    sub     rsp, DBUFSZ + 16
.ct_read:
    mov     rdi, r12
    mov     rsi, rsp
    mov     rdx, DBUFSZ
    call    uolt_getdents
    test    rax, rax
    jle     .ct_endread
    mov     [rsp + DBUFSZ], rax
    mov     qword ptr [rsp + DBUFSZ + 8], 0
.ct_ent:
    mov     rcx, [rsp + DBUFSZ + 8]
    cmp     rcx, [rsp + DBUFSZ]
    jae     .ct_read
    lea     rsi, [rsp + rcx + DIRENT_NAME_OFF]
    movzx   rax, word ptr [rsp + rcx + DIRENT_RECLEN_OFF]
    test    rax, rax
    jz      .ct_read
    add     rax, rcx
    mov     [rsp + DBUFSZ + 8], rax
    cmp     byte ptr [rsi], '.'
    jne     .ct_do
    cmp     byte ptr [rsi + 1], 0
    je      .ct_ent
    cmp     byte ptr [rsi + 1], '.'
    jne     .ct_do
    cmp     byte ptr [rsi + 2], 0
    je      .ct_ent
.ct_do:
    // append "/name" to both paths (rsi = entry name)
    mov     r8, rsi
    mov     byte ptr [r15 + rbx], '/'
    lea     rdi, [r15 + rbx + 1]
    call    .ct_appendfrom              // rdi = dst, r8 = name -> rdi past NUL
    sub     rdi, r15
    mov     r9, rdi                     // new src length (r9 survives the calls)
    mov     r8, rsi                     // reset name (the first append advanced r8)
    mov     byte ptr [r15 + PATHMAX + r13], '/'
    lea     rdi, [r15 + PATHMAX + r13 + 1]
    call    .ct_appendfrom
    lea     rax, [r15 + PATHMAX]
    sub     rdi, rax                    // new dst length
    mov     rsi, rdi                    // copy_tree(new src len, new dst len)
    mov     rdi, r9
    call    copy_tree
    jmp     .ct_ent
.ct_endread:
    add     rsp, DBUFSZ + 16
    mov     rdi, r12
    call    uolt_close
    jmp     .ct_ret
.ct_notdir:
    cmp     rax, -ENOTDIR
    jne     .ct_diag
    mov     rdi, r15                    // a file: copy it
    lea     rsi, [r15 + PATHMAX]
    call    copy_file
    jmp     .ct_ret
.ct_diag:
    mov     qword ptr [rbp + LOC_STAT], 1
    mov     rdi, r15
    call    .cp_diag
.ct_ret:
    pop     r13
    pop     r12
    pop     rbx
    ret

// .ct_appendfrom(rdi = dst, r8 = ASCIZ name) -> rdi past the copied NUL.
.ct_appendfrom:
    mov     al, [r8]
    mov     [rdi], al
    test    al, al
    jz      1f
    inc     r8
    inc     rdi
    jmp     .ct_appendfrom
1:
    ret

// copy_file(rdi = src path, rsi = dst path): copy contents. Uses the copy buffer
// at r15 + 2*PATHMAX. On failure sets LOC_STAT and diagnoses.
copy_file:
    push    rbx
    push    r12
    push    r13
    push    rdi                         // [rsp+8] = src path
    push    rsi                         // [rsp]   = dst path
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    call    uolt_open                   // rdi = src path
    test    rax, rax
    js      .cf_srcerr
    mov     r12, rax                    // src fd
    mov     rdi, [rsp]                  // dst path
    mov     rsi, FMODE
    call    uolt_opendst
    test    rax, rax
    js      .cf_dsterr
    mov     r13, rax                    // dst fd
.cf_cpy:
    mov     rdi, r12
    lea     rsi, [r15 + 2*PATHMAX]
    mov     rdx, BUFSZ
    call    uolt_read
    test    rax, rax
    jz      .cf_done
    js      .cf_cerr
    mov     rbx, rax
    lea     r9, [r15 + 2*PATHMAX]
.cf_wr:
    mov     rdi, r13
    mov     rsi, r9
    mov     rdx, rbx
    call    uolt_write
    test    rax, rax
    js      .cf_cerr
    add     r9, rax
    sub     rbx, rax
    jnz     .cf_wr
    jmp     .cf_cpy
.cf_done:
    mov     rdi, r12
    call    uolt_close
    mov     rdi, r13
    call    uolt_close
    jmp     .cf_ret
.cf_cerr:
    mov     rdi, r12
    call    uolt_close
    mov     rdi, r13
    call    uolt_close
    mov     rdi, [rsp]                  // dst path
    call    .cp_diag
    jmp     .cf_ret
.cf_dsterr:
    mov     rdi, r12
    call    uolt_close
    mov     rdi, [rsp]
    call    .cp_diag
    jmp     .cf_ret
.cf_srcerr:
    mov     rdi, [rsp + 8]              // src path
    call    .cp_diag
.cf_ret:
    add     rsp, 16
    pop     r13
    pop     r12
    pop     rbx
    ret

// .cp_diag(rdi = path string): "uolt-cp: <path>: cannot copy" to stderr, status 1.
.cp_diag:
    push    rbx
    mov     qword ptr [rbp + LOC_STAT], 1
    mov     rbx, rdi                    // save the path (err_puts clobbers r10)
    lea     rdi, [rip + err_pre]
    call    err_puts
    mov     rdi, rbx
    call    err_puts
    lea     rdi, [rip + err_suf]
    call    err_puts
    pop     rbx
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
    mov     r10, rdi
    call    uolt_strlen
    mov     rdx, rax
    mov     rsi, r10
    mov     rdi, STDERR
    jmp     uolt_write

err_usage: .asciz "uolt-cp: usage: cp [-r] source target\n"
err_pre:   .asciz "uolt-cp: "
err_suf:   .asciz ": cannot copy\n"
