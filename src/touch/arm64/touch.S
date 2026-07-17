// src/touch/arm64/touch.S - the POSIX `touch` utility (aarch64).
//
// touch [-c] [-a] [-m] file...: set each file's times to now, creating an empty
// file if missing. -c: do not create (a missing file is not an error). -a/-m
// accepted and ignored (both times always updated). Create via uolt_create +
// close, then uolt_utimes(path, NULL). A real failure -> stderr diagnostic,
// exit 1, remaining operands still processed. No heap. Mirrors the x86_64 body.
//
// Callee-saved roles: x19 = operand count, x20 = &argv walk, x21 = exit status,
//   x22 = -c flag, x23 = current path.

#include "uolt.inc"

.set STDERR, 2
.set MODE,   0666
.set ENOENT, 2

.text
.globl uolt_main
uolt_main:
    stp     x19, x20, [sp, #-48]!
    stp     x21, x22, [sp, #16]
    stp     x23, x30, [sp, #32]

    sub     x19, x0, #1
    add     x20, x1, #8
    mov     x21, #0
    mov     x22, #0                     // -c flag
.Lopt:
    cbz     x19, .Lafter
    ldr     x23, [x20]
    ldrb    w9, [x23]
    cmp     w9, #'-'
    b.ne    .Lafter
    ldrb    w9, [x23, #1]
    cbz     w9, .Lafter                 // "-" -> a file named "-"
    cmp     w9, #'-'
    b.ne    .Lflags
    ldrb    w9, [x23, #2]
    cbnz    w9, .Lflags
    add     x20, x20, #8                // "--"
    sub     x19, x19, #1
    b       .Lafter
.Lflags:
    add     x10, x23, #1                // validate letters (c/a/m only)
    mov     x11, x10
.Lval:
    ldrb    w9, [x11]
    cbz     w9, .Lapply
    cmp     w9, #'c'
    b.eq    1f
    cmp     w9, #'a'
    b.eq    1f
    cmp     w9, #'m'
    b.eq    1f
    b       .Lafter                     // unknown letter -> operand
1:
    add     x11, x11, #1
    b       .Lval
.Lapply:
    mov     x11, x10
.Lap:
    ldrb    w9, [x11]
    cbz     w9, .Lap_done
    cmp     w9, #'c'
    b.ne    2f
    mov     x22, #1                     // -c
2:
    add     x11, x11, #1
    b       .Lap
.Lap_done:
    add     x20, x20, #8
    sub     x19, x19, #1
    b       .Lopt
.Lafter:
    cbz     x19, .Lusage
.Lloop:
    cbz     x19, .Lfin
    ldr     x23, [x20]
    cbnz    x22, .Lstamp                // -c: skip creation
    mov     x0, x23
    mov     x1, #MODE
    bl      uolt_create
    cmp     x0, #0
    b.mi    .Ldiag_next                 // could not create
    mov     x0, x0
    bl      uolt_close
.Lstamp:
    mov     x0, x23                     // utimes(path, NULL) -> both times = now
    mov     x1, #0
    bl      uolt_utimes
    cmp     x0, #0
    b.ge    .Lnext
    cmn     x0, #ENOENT                 // -ENOENT ?
    b.ne    .Ldiag
    cbnz    x22, .Lnext                 // -c and ENOENT -> ignore
.Ldiag:
    mov     x21, #1
    adr     x0, err_pre
    bl      err_puts
    mov     x0, x23
    bl      err_puts
    adr     x0, err_suf
    bl      err_puts
    b       .Lnext
.Ldiag_next:
    bl      do_diag
.Lnext:
    add     x20, x20, #8
    sub     x19, x19, #1
    b       .Lloop
.Lfin:
    mov     x0, x21
    b       .Lret
.Lusage:
    adr     x0, err_usage
    bl      err_puts
    mov     x0, #1
.Lret:
    ldp     x21, x22, [sp, #16]
    ldp     x23, x30, [sp, #32]
    ldp     x19, x20, [sp], #48
    ret

// do_diag(x23 = path): shared diagnostic for the create-failure path.
do_diag:
    stp     x29, x30, [sp, #-16]!
    mov     x21, #1
    adr     x0, err_pre
    bl      err_puts
    mov     x0, x23
    bl      err_puts
    adr     x0, err_suf
    bl      err_puts
    ldp     x29, x30, [sp], #16
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

err_usage: .asciz "uolt-touch: usage: touch [-c] file...\n"
err_pre:   .asciz "uolt-touch: "
err_suf:   .asciz ": cannot touch\n"
