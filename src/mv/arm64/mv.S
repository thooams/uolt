// src/mv/arm64/mv.S - the POSIX `mv` utility (aarch64).
//
// mv source target | mv source... directory. A directory final operand moves
// each source to "directory/basename(source)"; otherwise exactly two operands
// and source -> target. rename atomically replaces an existing target. Cross
// -device moves (EXDEV) are not handled in v1. Failure -> stderr diagnostic,
// exit 1. No heap: the "dir/name" path is built in a stack buffer. Mirrors x86_64.
//
// Callee-saved: x19 = operand count, x20 = &argv walk, x21 = exit status,
//   x22 = path buffer base, x23 = current source. Locals off x29.

#include "uolt.inc"

.set STDERR,  2
.set S_IFDIR, 0040000
.set LOC_DIR,  48               // directory path (0 = not dir mode)
.set LOC_SIDX, 56               // source index (dir mode)
.set PATHBUF,  64
.set FRAME,    4160

.text
.globl uolt_main
uolt_main:
    mov     x9, #FRAME
    sub     sp, sp, x9
    mov     x29, sp
    stp     x19, x20, [sp, #0]
    stp     x21, x22, [sp, #16]
    stp     x23, x30, [sp, #32]
    add     x22, x29, #PATHBUF          // buffer base
    mov     x21, #0
    str     xzr, [x29, #LOC_DIR]
    str     xzr, [x29, #LOC_SIDX]

    sub     x19, x0, #1
    add     x20, x1, #8
    cbz     x19, .Lusage

    // optional "--"
    ldr     x9, [x20]
    ldrb    w10, [x9]
    cmp     w10, #'-'
    b.ne    .Lafter
    ldrb    w10, [x9, #1]
    cmp     w10, #'-'
    b.ne    .Lafter
    ldrb    w10, [x9, #2]
    cbnz    w10, .Lafter
    add     x20, x20, #8
    sub     x19, x19, #1
.Lafter:
    cmp     x19, #2
    b.lt    .Lusage

    // Is the last operand a directory?
    add     x9, x20, x19, lsl #3
    ldr     x0, [x9, #-8]
    bl      uolt_statmode
    cmp     x0, #0
    b.mi    .Lnot_dir
    and     x0, x0, #0170000
    mov     x9, #S_IFDIR
    cmp     x0, x9
    b.ne    .Lnot_dir

    add     x9, x20, x19, lsl #3        // directory path
    ldr     x9, [x9, #-8]
    str     x9, [x29, #LOC_DIR]
.Ldloop:
    ldr     x9, [x29, #LOC_SIDX]
    sub     x10, x19, #1                // number of sources
    cmp     x9, x10
    b.hs    .Lfin
    ldr     x23, [x20, x9, lsl #3]      // source
    ldr     x1, [x29, #LOC_DIR]         // dir
    mov     x0, x22                     // dst
    bl      copy_str                    // x0 = dir length
    mov     x9, x0
    mov     w10, #'/'
    strb    w10, [x22, x9]
    add     x9, x9, #1
    mov     x11, x23                    // basename(src)
    mov     x1, x23
.Lbn:
    ldrb    w10, [x11]
    cbz     w10, .Lbn_done
    cmp     w10, #'/'
    b.ne    1f
    add     x1, x11, #1
1:
    add     x11, x11, #1
    b       .Lbn
.Lbn_done:
    add     x12, x22, x9                // append basename at [buf + rcx]
    mov     x11, x1
.Lba:
    ldrb    w10, [x11]
    strb    w10, [x12]
    cbz     w10, .Lba_done
    add     x11, x11, #1
    add     x12, x12, #1
    b       .Lba
.Lba_done:
    mov     x0, x23                     // source
    mov     x1, x22                     // target
    bl      uolt_rename
    cmp     x0, #0
    b.mi    .Ldiag
.Ldnext:
    ldr     x9, [x29, #LOC_SIDX]
    add     x9, x9, #1
    str     x9, [x29, #LOC_SIDX]
    b       .Ldloop

.Lnot_dir:
    cmp     x19, #2
    b.ne    .Lusage
    ldr     x23, [x20]
    ldr     x0, [x20]
    ldr     x1, [x20, #8]
    bl      uolt_rename
    cmp     x0, #0
    b.mi    .Ldiag
    b       .Lfin

.Ldiag:
    mov     x21, #1
    adr     x0, err_pre
    bl      err_puts
    mov     x0, x23
    bl      err_puts
    adr     x0, err_suf
    bl      err_puts
    ldr     x9, [x29, #LOC_DIR]         // dir mode -> continue with remaining
    cbz     x9, .Lfin
    b       .Ldnext

.Lfin:
    mov     x0, x21
.Lret:
    ldp     x19, x20, [sp, #0]
    ldp     x21, x22, [sp, #16]
    ldp     x23, x30, [sp, #32]
    mov     x9, #FRAME
    add     sp, sp, x9
    ret
.Lusage:
    adr     x0, err_usage
    bl      err_puts
    mov     x0, #1
    b       .Lret

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

err_usage: .asciz "uolt-mv: usage: mv source... target\n"
err_pre:   .asciz "uolt-mv: "
err_suf:   .asciz ": cannot move\n"
