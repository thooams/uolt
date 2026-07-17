// src/ln/arm64/ln.S - the POSIX `ln` utility (aarch64).
//
// ln [-s] [-f] source [target] | ln [-s] [-f] source... directory. Hard link by
// default, symbolic with -s; -f removes an existing target first. Omitted target
// -> basename(source) in cwd. A directory final operand -> link each source to
// dir/basename(source). Failure -> stderr diagnostic, exit 1. No heap: the
// "dir/name" path is built in a stack buffer. Mirrors the x86_64 body.
//
// Callee-saved: x19 = operand count, x20 = &argv walk, x21 = exit status,
//   x22 = flags (bit0 -s, bit1 -f), x23 = source. Locals off x29.

#include "uolt.inc"

.set STDERR,  2
.set S_IFDIR, 0040000
.set LOC_IDX, 48
.set PATHBUF, 64
.set FRAME,   4160              // PATHBUF + 4096

.text
.globl uolt_main
uolt_main:
    mov     x9, #FRAME
    sub     sp, sp, x9
    mov     x29, sp
    stp     x19, x20, [sp, #0]
    stp     x21, x22, [sp, #16]
    stp     x23, x30, [sp, #32]

    sub     x19, x0, #1
    add     x20, x1, #8
    mov     x21, #0
    mov     x22, #0                     // flags
.Lopt:
    cbz     x19, .Lafter
    ldr     x23, [x20]
    ldrb    w9, [x23]
    cmp     w9, #'-'
    b.ne    .Lafter
    ldrb    w9, [x23, #1]
    cbz     w9, .Lafter
    cmp     w9, #'-'
    b.eq    .Lmaybe_ddash
    add     x11, x23, #1                // validate letters are s/f
.Lv:
    ldrb    w9, [x11]
    cbz     w9, .Lapply
    cmp     w9, #'s'
    b.eq    1f
    cmp     w9, #'f'
    b.eq    1f
    b       .Lafter
1:
    add     x11, x11, #1
    b       .Lv
.Lapply:
    add     x11, x23, #1
.La:
    ldrb    w9, [x11]
    cbz     w9, .Ladone
    cmp     w9, #'s'
    b.ne    2f
    orr     x22, x22, #1
2:
    cmp     w9, #'f'
    b.ne    3f
    orr     x22, x22, #2
3:
    add     x11, x11, #1
    b       .La
.Ladone:
    add     x20, x20, #8
    sub     x19, x19, #1
    b       .Lopt
.Lmaybe_ddash:
    ldrb    w9, [x23, #2]
    cbnz    w9, .Lafter
    add     x20, x20, #8
    sub     x19, x19, #1
.Lafter:
    cbz     x19, .Lusage
    cmp     x19, #1
    b.eq    .Limplicit
    // Two or more operands: if the last is a directory, link into it.
    add     x9, x20, x19, lsl #3
    ldr     x0, [x9, #-8]
    bl      uolt_statmode
    cmp     x0, #0
    b.mi    .Lexplicit
    and     x0, x0, #0170000
    mov     x9, #S_IFDIR
    cmp     x0, x9
    b.eq    .Linto_dir
.Lexplicit:
    cmp     x19, #2
    b.ne    .Lusage
    ldr     x23, [x20]                  // source
    ldr     x1, [x20, #8]               // target
    bl      do_link
    b       .Lfin
.Limplicit:
    ldr     x23, [x20]                  // source
    mov     x1, x23                     // target = basename(source)
    mov     x9, #0
.Lbl:
    ldrb    w10, [x23, x9]
    cbz     w10, .Lbldone
    cmp     w10, #'/'
    b.ne    4f
    add     x1, x23, x9
    add     x1, x1, #1
4:
    add     x9, x9, #1
    b       .Lbl
.Lbldone:
    bl      do_link
    b       .Lfin
.Linto_dir:
    str     xzr, [x29, #LOC_IDX]
.Lid_loop:
    ldr     x9, [x29, #LOC_IDX]
    sub     x10, x19, #1                // number of sources
    cmp     x9, x10
    b.hs    .Lfin
    ldr     x23, [x20, x9, lsl #3]      // source
    add     x0, x29, #PATHBUF           // dst
    add     x11, x20, x19, lsl #3
    ldr     x1, [x11, #-8]              // directory
    bl      copy_str                    // x0 = dir length
    add     x9, x29, #PATHBUF
    add     x9, x9, x0                  // &buf[dirlen]
    mov     w10, #'/'
    strb    w10, [x9]
    add     x9, x9, #1
    mov     x11, x23                    // basename(src)
    mov     x1, x23
.Lid_bn:
    ldrb    w10, [x11]
    cbz     w10, .Lid_bnd
    cmp     w10, #'/'
    b.ne    5f
    add     x1, x11, #1
5:
    add     x11, x11, #1
    b       .Lid_bn
.Lid_bnd:
    mov     x11, x1                     // append basename at x9
6:
    ldrb    w10, [x11]
    strb    w10, [x9]
    cbz     w10, 7f
    add     x11, x11, #1
    add     x9, x9, #1
    b       6b
7:
    add     x1, x29, #PATHBUF           // target path
    bl      do_link
    ldr     x9, [x29, #LOC_IDX]
    add     x9, x9, #1
    str     x9, [x29, #LOC_IDX]
    b       .Lid_loop
.Lfin:
    mov     x0, x21
    b       .Lret
.Lusage:
    adr     x0, err_usage
    bl      err_puts
    mov     x0, #1
.Lret:
    ldp     x19, x20, [sp, #0]
    ldp     x21, x22, [sp, #16]
    ldp     x23, x30, [sp, #32]
    mov     x9, #FRAME
    add     sp, sp, x9
    ret

// do_link(x23 = source, x1 = target): create the link honoring -s/-f. x9 = target
// (survives the wrapper calls). Sets x21 and diagnoses on failure.
do_link:
    stp     x29, x30, [sp, #-16]!
    mov     x9, x1                      // target
    tst     x22, #2                     // -f: remove existing target first
    b.eq    .Ldl_nf
    mov     x0, x9
    bl      uolt_unlink                 // ignore result
.Ldl_nf:
    tst     x22, #1                     // -s?
    b.eq    .Ldl_hard
    mov     x0, x23
    mov     x1, x9
    bl      uolt_symlink
    b       .Ldl_chk
.Ldl_hard:
    mov     x0, x23
    mov     x1, x9
    bl      uolt_link
.Ldl_chk:
    cmp     x0, #0
    b.ge    .Ldl_ret
    mov     x21, #1
    adr     x0, err_pre
    bl      err_puts
    mov     x0, x9
    bl      err_puts
    adr     x0, err_suf
    bl      err_puts
.Ldl_ret:
    ldp     x29, x30, [sp], #16
    ret

// copy_str(x0 = dst, x1 = src ASCIZ) -> x0 = length copied. Leaf.
copy_str:
    mov     x2, #0
1:
    ldrb    w3, [x1, x2]
    strb    w3, [x0, x2]
    cbz     w3, 2f
    add     x2, x2, #1
    b       1b
2:
    mov     x0, x2
    ret

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

err_usage: .asciz "uolt-ln: usage: ln [-s] [-f] source... [target]\n"
err_pre:   .asciz "uolt-ln: "
err_suf:   .asciz ": cannot create link\n"
