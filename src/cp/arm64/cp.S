// src/cp/arm64/cp.S - the `cp` utility (file copy, plus recursive -r), aarch64.
//
// cp source target        copy a file's contents to target
// cp -r source target      copy a directory tree to target
//
// Data streams through one 64 KB buffer (no heap, Principle IV). With -r,
// directories are walked recursively (opendir/getdents) and re-created (mkdir);
// two path buffers - source and target - grow in parallel and truncate on return.
// Files get 0666 (umask-masked), directories 0777. When the final operand is an
// existing directory, each source is copied to dir/basename(source). Mirrors the
// x86_64 body.
//
// Global: x19 = base of (srcbuf[PATHMAX] dstbuf[PATHMAX] copybuf[BUFSZ]). Locals
// off x29. main: x20 = operand count then dst length; x21 = &argv walk; x22 =
// source index; x23 = src length.

#include "uolt.inc"

.set STDERR,   2
.set O_RDONLY, 0
.set ENOTDIR,  20
.set FMODE,    0666
.set DMODE,    0777
.set BUFSZ,    65536
.set PATHMAX,  4096
.set DBUFSZ,   4096

.set LOC_STAT, 56
.set LOC_R,    64
.set LOC_DIR,  72

.set S_IFMT_L,  0170000
.set S_IFDIR_L, 0040000

.text
.globl uolt_main
uolt_main:
    sub     sp, sp, #80
    mov     x29, sp
    str     x30, [x29, #0]
    stp     x19, x20, [x29, #16]
    stp     x21, x22, [x29, #32]
    str     x23, [x29, #48]
    sub     sp, sp, #73728             // 2*PATHMAX + BUFSZ
    sub     sp, sp, #64
    mov     x19, sp
    str     xzr, [x29, #LOC_STAT]
    str     xzr, [x29, #LOC_R]
    sub     x20, x0, #1                // operand count
    add     x21, x1, #8                // &argv[1]
.opt:
    cbz     x20, .usage
    ldr     x9, [x21]
    ldrb    w10, [x9]
    cmp     w10, #'-'
    b.ne    .after
    ldrb    w10, [x9, #1]
    cbz     w10, .after
    cmp     w10, #'-'
    b.eq    .ddash
    add     x11, x9, #1
.optf:
    ldrb    w10, [x11]
    cbz     w10, .optnext
    cmp     w10, #'r'
    b.eq    .optf_r
    cmp     w10, #'R'
    b.ne    .after
.optf_r:
    mov     x12, #1
    str     x12, [x29, #LOC_R]
    add     x11, x11, #1
    b       .optf
.optnext:
    add     x21, x21, #8
    sub     x20, x20, #1
    b       .opt
.ddash:
    ldrb    w10, [x9, #2]
    cbnz    w10, .after
    add     x21, x21, #8
    sub     x20, x20, #1
.after:
    cmp     x20, #2
    b.lt    .usage
    sub     x9, x20, #1                // final operand an existing directory?
    ldr     x0, [x21, x9, lsl #3]
    bl      uolt_statmode
    cmp     x0, #0
    b.mi    .two
    and     x0, x0, #S_IFMT_L
    cmp     x0, #S_IFDIR_L
    b.ne    .two

    // Into-directory form: dst = dir/basename(source) for each source.
    sub     x9, x20, #1
    ldr     x9, [x21, x9, lsl #3]
    str     x9, [x29, #LOC_DIR]
    mov     x22, #0                    // source index
.id_loop:
    sub     x9, x20, #1                // number of sources
    cmp     x22, x9
    b.hs    .fin
    ldr     x1, [x21, x22, lsl #3]     // source into srcbuf
    mov     x0, x19
    bl      .copy_str
    mov     x23, x0                    // src length
    ldr     x1, [x29, #LOC_DIR]        // dir into dstbuf
    add     x0, x19, #PATHMAX
    bl      .copy_str
    add     x9, x19, #PATHMAX
    mov     w10, #'/'
    strb    w10, [x9, x0]
    add     x0, x0, #1                 // position after "dir/"
    ldr     x2, [x21, x22, lsl #3]     // basename of source
    mov     x3, x2
.id_bn:
    ldrb    w10, [x2]
    cbz     w10, .id_bndone
    cmp     w10, #'/'
    b.ne    .id_bn_adv
    add     x3, x2, #1
.id_bn_adv:
    add     x2, x2, #1
    b       .id_bn
.id_bndone:
    add     x9, x19, #PATHMAX
    add     x4, x9, x0                 // dst append cursor
    mov     x5, x3                     // basename
.id_cpy:
    ldrb    w10, [x5]
    strb    w10, [x4]
    cbz     w10, .id_cpydone
    add     x5, x5, #1
    add     x4, x4, #1
    b       .id_cpy
.id_cpydone:
    add     x9, x19, #PATHMAX
    sub     x4, x4, x9                 // dst length
    ldr     x9, [x29, #LOC_R]
    cbnz    x9, .id_tree
    mov     x0, x19
    add     x1, x19, #PATHMAX
    bl      copy_file
    b       .id_next
.id_tree:
    mov     x1, x4                     // dst length
    mov     x0, x23                    // src length
    bl      copy_tree
.id_next:
    add     x22, x22, #1
    b       .id_loop

.two:
    cmp     x20, #2
    b.ne    .usage
    mov     x0, x19
    ldr     x1, [x21]
    bl      .copy_str
    mov     x23, x0                    // src length
    add     x0, x19, #PATHMAX
    ldr     x1, [x21, #8]
    bl      .copy_str
    mov     x20, x0                    // dst length
    ldr     x9, [x29, #LOC_R]
    cbnz    x9, .recursive
    mov     x0, x19
    add     x1, x19, #PATHMAX
    bl      copy_file
    b       .fin
.recursive:
    mov     x0, x23
    mov     x1, x20
    bl      copy_tree

.fin:
    ldr     x0, [x29, #LOC_STAT]
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
    add     sp, sp, #73728
    add     sp, sp, #64
    ret

// copy_tree(x0 = src length, x1 = dst length): copy the source (file or tree) at
// srcbuf to dstbuf. Per-level frame holds the directory buffer + scan state, so
// recursion is safe. x23 = src length, x24 = dst length, x25 = src dir fd.
// Frame: [0]x23,x24 [16]x25,x30 [32]bytes [40]index [48]namebase [56]newsrclen
//        [64..64+DBUFSZ) dirbuf.
copy_tree:
    sub     sp, sp, #4096
    sub     sp, sp, #64
    stp     x23, x24, [sp, #0]
    stp     x25, x30, [sp, #16]
    mov     x23, x0
    mov     x24, x1
    strb    wzr, [x19, x23]            // NUL-terminate src path
    add     x9, x19, #PATHMAX
    strb    wzr, [x9, x24]             // NUL-terminate dst path
    mov     x0, x19
    bl      uolt_opendir
    cmp     x0, #0
    b.mi    .ct_notdir
    mov     x25, x0                    // source directory fd
    add     x0, x19, #PATHMAX          // create the target directory
    mov     x1, #DMODE
    bl      uolt_mkdir                 // ignore result (EEXIST ok)
.ct_read:
    mov     x0, x25
    add     x1, sp, #64
    mov     x2, #DBUFSZ
    bl      uolt_getdents
    cmp     x0, #0
    b.le    .ct_endread
    str     x0, [sp, #32]              // bytes
    str     xzr, [sp, #40]             // index
.ct_ent:
    ldr     x9, [sp, #40]
    ldr     x10, [sp, #32]
    cmp     x9, x10
    b.hs    .ct_read
    add     x11, sp, #64
    add     x11, x11, x9               // &dirent
    add     x10, x11, #DIRENT_NAME_OFF // name ptr
    ldrh    w12, [x11, #DIRENT_RECLEN_OFF]
    cbz     w12, .ct_read
    add     x12, x12, x9
    str     x12, [sp, #40]             // advance index
    ldrb    w13, [x10]
    cmp     w13, #'.'
    b.ne    .ct_do
    ldrb    w13, [x10, #1]
    cbz     w13, .ct_ent
    cmp     w13, #'.'
    b.ne    .ct_do
    ldrb    w13, [x10, #2]
    cbz     w13, .ct_ent
.ct_do:
    str     x10, [sp, #48]             // name base
    mov     w13, #'/'
    strb    w13, [x19, x23]            // append "/name" to src
    add     x0, x19, x23
    add     x0, x0, #1
    mov     x1, x10
    bl      .ct_appendfrom
    sub     x9, x0, x19
    str     x9, [sp, #56]              // new src length
    add     x9, x19, #PATHMAX
    mov     w13, #'/'
    strb    w13, [x9, x24]             // append "/name" to dst
    add     x0, x9, x24
    add     x0, x0, #1
    ldr     x1, [sp, #48]              // name base
    bl      .ct_appendfrom
    add     x9, x19, #PATHMAX
    sub     x1, x0, x9                 // new dst length
    ldr     x0, [sp, #56]              // new src length
    bl      copy_tree
    b       .ct_ent
.ct_endread:
    mov     x0, x25
    bl      uolt_close
    b       .ct_ret
.ct_notdir:
    cmn     x0, #ENOTDIR
    b.ne    .ct_diag
    mov     x0, x19                    // a file: copy it
    add     x1, x19, #PATHMAX
    bl      copy_file
    b       .ct_ret
.ct_diag:
    mov     x9, #1
    str     x9, [x29, #LOC_STAT]
    mov     x0, x19
    bl      .cp_diag
.ct_ret:
    ldp     x23, x24, [sp, #0]
    ldp     x25, x30, [sp, #16]
    add     sp, sp, #4096
    add     sp, sp, #64
    ret

// .ct_appendfrom(x0 = dst, x1 = ASCIZ name) -> x0 past the copied NUL. Leaf.
.ct_appendfrom:
    ldrb    w2, [x1]
    strb    w2, [x0]
    cbz     w2, .ctaf_done
    add     x1, x1, #1
    add     x0, x0, #1
    b       .ct_appendfrom
.ctaf_done:
    ret

// copy_file(x0 = src path, x1 = dst path): copy contents via the copy buffer at
// x19 + 2*PATHMAX. On failure sets LOC_STAT and diagnoses. x24 = src fd, x25 = dst
// fd, x26 = read count, x27 = write ptr.
copy_file:
    sub     sp, sp, #64
    stp     x24, x25, [sp, #0]
    stp     x26, x27, [sp, #16]
    str     x30, [sp, #32]
    str     x0, [sp, #40]              // src path
    str     x1, [sp, #48]              // dst path
    mov     x1, #O_RDONLY
    mov     x2, #0
    bl      uolt_open                  // x0 = src path
    cmp     x0, #0
    b.mi    .cf_srcerr
    mov     x24, x0                    // src fd
    ldr     x0, [sp, #48]              // dst path
    mov     x1, #FMODE
    bl      uolt_opendst
    cmp     x0, #0
    b.mi    .cf_dsterr
    mov     x25, x0                    // dst fd
.cf_cpy:
    mov     x0, x24
    add     x1, x19, #8192             // 2*PATHMAX copy buffer
    mov     x2, #BUFSZ
    bl      uolt_read
    cmp     x0, #0
    b.eq    .cf_done
    b.mi    .cf_cerr
    mov     x26, x0                    // read count
    add     x27, x19, #8192           // write ptr
.cf_wr:
    mov     x0, x25
    mov     x1, x27
    mov     x2, x26
    bl      uolt_write
    cmp     x0, #0
    b.mi    .cf_cerr
    add     x27, x27, x0
    subs    x26, x26, x0
    b.ne    .cf_wr
    b       .cf_cpy
.cf_done:
    mov     x0, x24
    bl      uolt_close
    mov     x0, x25
    bl      uolt_close
    b       .cf_ret
.cf_cerr:
    mov     x0, x24
    bl      uolt_close
    mov     x0, x25
    bl      uolt_close
    ldr     x0, [sp, #48]
    bl      .cp_diag
    b       .cf_ret
.cf_dsterr:
    mov     x0, x24
    bl      uolt_close
    ldr     x0, [sp, #48]
    bl      .cp_diag
    b       .cf_ret
.cf_srcerr:
    ldr     x0, [sp, #40]
    bl      .cp_diag
.cf_ret:
    ldp     x24, x25, [sp, #0]
    ldp     x26, x27, [sp, #16]
    ldr     x30, [sp, #32]
    add     sp, sp, #64
    ret

// .cp_diag(x0 = path): "uolt-cp: <path>: cannot copy" to stderr, status 1. x23 = path.
.cp_diag:
    stp     x23, x30, [sp, #-16]!
    mov     x9, #1
    str     x9, [x29, #LOC_STAT]
    mov     x23, x0
    adr     x0, err_pre
    bl      err_puts
    mov     x0, x23
    bl      err_puts
    adr     x0, err_suf
    bl      err_puts
    ldp     x23, x30, [sp], #16
    ret

// .copy_str(x0 = dst, x1 = src ASCIZ) -> x0 = length copied. Leaf.
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

err_usage: .asciz "uolt-cp: usage: cp [-r] source target\n"
err_pre:   .asciz "uolt-cp: "
err_suf:   .asciz ": cannot copy\n"
