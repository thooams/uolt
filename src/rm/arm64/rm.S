// src/rm/arm64/rm.S - the POSIX `rm` utility, aarch64.
//
// rm [-f] [-r|-R] file...: remove files, and with -r/-R remove directory trees.
// With -f, non-existent operands are ignored and an empty list is success. Without
// -r a directory operand is an error. Mirrors the x86_64 body.
//
// Recursive removal reopens the directory each pass so no read position is held
// across recursion: a single directory buffer and a single path buffer are reused
// at every level (no heap, Principle IV). The path buffer grows by appending
// "/name" and is truncated on return; depth is bounded by the process stack.
//
// Callee-saved: x19 = path buffer; x20 = directory buffer; x21 = exit status;
//   x22 = operand count; x23 = current path / rm_tree level length. Locals off x29.

#include "uolt.inc"

.set STDERR,   2
.set ENOENT,   2
.set ENOTDIR,  20
.set PATHMAX,  4096
.set DBUFSZ,   32768

.set LOC_ARGV,  56
.set LOC_FLAGS, 64

.text
.globl uolt_main
uolt_main:
    sub     sp, sp, #80
    mov     x29, sp
    str     x30, [x29, #0]
    stp     x19, x20, [x29, #16]
    stp     x21, x22, [x29, #32]
    str     x23, [x29, #48]
    sub     sp, sp, #36864             // PATHMAX + DBUFSZ
    sub     sp, sp, #16
    mov     x19, sp                    // path buffer
    add     x20, x19, #PATHMAX         // directory buffer
    mov     x21, #0                    // exit status
    str     xzr, [x29, #LOC_FLAGS]
    sub     x22, x0, #1                // operand count
    add     x23, x1, #8                // &argv walk
.opt:
    cbz     x22, .after
    ldr     x9, [x23]
    ldrb    w10, [x9]
    cmp     w10, #'-'
    b.ne    .after
    ldrb    w10, [x9, #1]
    cbz     w10, .after
    cmp     w10, #'-'
    b.eq    .ddash
    add     x3, x9, #1                 // validate letters f/r/R
    mov     x4, x3
.v:
    ldrb    w10, [x3]
    cbz     w10, .apply
    cmp     w10, #'f'
    b.eq    .v_ok
    cmp     w10, #'r'
    b.eq    .v_ok
    cmp     w10, #'R'
    b.eq    .v_ok
    b       .after
.v_ok:
    add     x3, x3, #1
    b       .v
.apply:
    mov     x3, x4
.ap:
    ldrb    w10, [x3]
    cbz     w10, .apd
    cmp     w10, #'f'
    b.ne    .ap2
    ldr     x11, [x29, #LOC_FLAGS]
    orr     x11, x11, #1
    str     x11, [x29, #LOC_FLAGS]
.ap2:
    cmp     w10, #'r'
    b.eq    .ap_r
    cmp     w10, #'R'
    b.ne    .ap4
.ap_r:
    ldr     x11, [x29, #LOC_FLAGS]
    orr     x11, x11, #2
    str     x11, [x29, #LOC_FLAGS]
.ap4:
    add     x3, x3, #1
    b       .ap
.apd:
    add     x23, x23, #8
    sub     x22, x22, #1
    b       .opt
.ddash:
    ldrb    w10, [x9, #2]
    cbnz    w10, .after
    add     x23, x23, #8
    sub     x22, x22, #1
.after:
    str     x23, [x29, #LOC_ARGV]
    cbnz    x22, .loop
    ldr     x9, [x29, #LOC_FLAGS]       // no operands: -f -> success, else usage
    tbnz    x9, #0, .fin
    b       .usage

.loop:
    cbz     x22, .fin
    ldr     x9, [x29, #LOC_ARGV]
    ldr     x23, [x9]                   // current path
    ldr     x9, [x29, #LOC_FLAGS]
    tbnz    x9, #1, .recursive
    mov     x0, x23                     // plain file removal
    bl      uolt_unlink
    cmp     x0, #0
    b.ge    .next
    cmn     x0, #ENOENT
    b.ne    .diag
    ldr     x9, [x29, #LOC_FLAGS]
    tbnz    x9, #0, .next               // -f + ENOENT -> ignore
    b       .diag
.recursive:
    mov     x0, x19
    mov     x1, x23
    bl      .copy_str                   // -> x0 = length
    bl      rm_tree
.next:
    ldr     x9, [x29, #LOC_ARGV]
    add     x9, x9, #8
    str     x9, [x29, #LOC_ARGV]
    sub     x22, x22, #1
    b       .loop
.diag:
    mov     x21, #1
    mov     x0, x23
    bl      .diag_path
    b       .next
.fin:
    mov     x0, x21
    b       .ret
.usage:
    adr     x0, err_usage
    bl      err_puts
    mov     x0, #1
.ret:
    mov     sp, x29
    ldr     x30, [x29, #0]
    ldp     x19, x20, [x29, #16]
    ldp     x21, x22, [x29, #32]
    ldr     x23, [x29, #48]
    add     sp, sp, #80
    ret

// rm_tree(x0 = path length in the path buffer): remove the tree rooted at the
// path. Reopens the directory each pass. x23 = this level's length, x24 = dir fd,
// x25 = getdents byte count.
rm_tree:
    sub     sp, sp, #48
    stp     x23, x24, [sp, #0]
    stp     x25, x30, [sp, #16]
    mov     x23, x0
.rt_loop:
    strb    wzr, [x19, x23]            // terminate the path here
    mov     x0, x19
    bl      uolt_opendir
    cmp     x0, #0
    b.mi    .rt_notdir
    mov     x24, x0                    // dir fd
    mov     x0, x24
    mov     x1, x20
    mov     x2, #DBUFSZ
    bl      uolt_getdents
    mov     x25, x0                    // bytes (survives close)
    mov     x0, x24
    bl      uolt_close
    cmp     x25, #0
    b.le    .rt_rmdir
    mov     x9, #0                     // scan index
.rt_scan:
    cmp     x9, x25
    b.hs    .rt_rmdir
    add     x10, x20, x9
    add     x10, x10, #DIRENT_NAME_OFF // name ptr
    ldrb    w11, [x10]
    cmp     w11, #'.'
    b.ne    .rt_found
    ldrb    w11, [x10, #1]
    cbz     w11, .rt_skip
    cmp     w11, #'.'
    b.ne    .rt_found
    ldrb    w11, [x10, #2]
    cbz     w11, .rt_skip
    b       .rt_found
.rt_skip:
    add     x11, x20, x9
    ldrh    w12, [x11, #DIRENT_RECLEN_OFF]
    cbz     w12, .rt_rmdir             // reclen 0 guard
    add     x9, x9, x12
    b       .rt_scan
.rt_found:
    mov     w11, #'/'                  // append "/name" at [x19 + x23]
    strb    w11, [x19, x23]
    add     x12, x19, x23
    add     x12, x12, #1               // dst
.rt_cpy:
    ldrb    w11, [x10]
    strb    w11, [x12]
    cbz     w11, .rt_cpydone
    add     x10, x10, #1
    add     x12, x12, #1
    b       .rt_cpy
.rt_cpydone:
    sub     x0, x12, x19               // new length = &NUL - base
    bl      rm_tree                    // recurse
    b       .rt_loop                   // reopen and take the next entry
.rt_notdir:
    cmn     x0, #ENOTDIR
    b.ne    .rt_patherr
    mov     x0, x19                    // a file: unlink it
    bl      uolt_unlink
    cmp     x0, #0
    b.mi    .rt_patherr_e
    b       .rt_ok
.rt_rmdir:
    mov     x0, x19
    bl      uolt_rmdir
    cmp     x0, #0
    b.mi    .rt_patherr_e
.rt_ok:
    ldp     x23, x24, [sp, #0]
    ldp     x25, x30, [sp, #16]
    add     sp, sp, #48
    ret
.rt_patherr:
    cmn     x0, #ENOENT
    b.ne    .rt_patherr_e
    ldr     x9, [x29, #LOC_FLAGS]
    tbnz    x9, #0, .rt_ok             // -f + ENOENT -> ignore
.rt_patherr_e:
    mov     x21, #1
    mov     x0, x19
    bl      .diag_path
    ldp     x23, x24, [sp, #0]
    ldp     x25, x30, [sp, #16]
    add     sp, sp, #48
    ret

// .copy_str(x0 = dst, x1 = src ASCIZ) -> x0 = length copied (excluding NUL). Leaf.
.copy_str:
    mov     x2, #0
.cs_l:
    ldrb    w3, [x1, x2]
    strb    w3, [x0, x2]
    cbz     w3, .cs_done
    add     x2, x2, #1
    b       .cs_l
.cs_done:
    mov     x0, x2
    ret

// .diag_path(x0 = path): "uolt-rm: <path>: cannot remove" to stderr. x23 = path.
.diag_path:
    stp     x23, x30, [sp, #-16]!
    mov     x23, x0
    adr     x0, err_pre
    bl      err_puts
    mov     x0, x23
    bl      err_puts
    adr     x0, err_suf
    bl      err_puts
    ldp     x23, x30, [sp], #16
    ret

// err_puts(x0 = ASCIZ) -> stderr. Saves lr.
err_puts:
    stp     x29, x30, [sp, #-16]!
    mov     x3, x0
    bl      uolt_strlen
    mov     x2, x0
    mov     x1, x3
    mov     x0, #STDERR
    bl      uolt_write
    ldp     x29, x30, [sp], #16
    ret

err_usage: .asciz "uolt-rm: usage: rm [-f] [-r] file...\n"
err_pre:   .asciz "uolt-rm: "
err_suf:   .asciz ": cannot remove\n"
