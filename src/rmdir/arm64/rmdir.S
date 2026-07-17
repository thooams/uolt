// src/rmdir/arm64/rmdir.S - the POSIX `rmdir` utility (aarch64).
//
// rmdir [-p] dir...: remove each empty directory. -p then removes now-empty
// ancestors, walking up until one is not removable. A failure -> stderr
// diagnostic, exit 1, remaining operands still processed. No heap (Principle IV):
// the -p walk shortens the operand string in place. Mirrors the x86_64 body.
//
// Callee-saved roles: x19 = operand count, x20 = &argv walk, x21 = exit status,
//   x22 = -p flag, x23 = current path.

#include "uolt.inc"

.set STDERR, 2

.text
.globl uolt_main
uolt_main:
    stp     x19, x20, [sp, #-48]!
    stp     x21, x22, [sp, #16]
    stp     x23, x30, [sp, #32]

    sub     x19, x0, #1
    add     x20, x1, #8
    mov     x21, #0
    mov     x22, #0
.Lopt:
    cbz     x19, .Lafter
    ldr     x23, [x20]
    ldrb    w9, [x23]
    cmp     w9, #'-'
    b.ne    .Lafter
    ldrb    w9, [x23, #1]
    cbz     w9, .Lafter
    cmp     w9, #'p'
    b.ne    1f
    ldrb    w9, [x23, #2]
    cbnz    w9, 1f
    mov     x22, #1
    add     x20, x20, #8
    sub     x19, x19, #1
    b       .Lopt
1:
    ldrb    w9, [x23, #1]
    cmp     w9, #'-'
    b.ne    .Lafter
    ldrb    w9, [x23, #2]
    cbnz    w9, .Lafter
    add     x20, x20, #8
    sub     x19, x19, #1
.Lafter:
    cbz     x19, .Lusage
.Lloop:
    cbz     x19, .Lfin
    ldr     x23, [x20]
    cbnz    x22, .Lp_mode
    mov     x0, x23
    bl      uolt_rmdir
    cmp     x0, #0
    b.ge    .Lnext
    bl      diag
    b       .Lnext
.Lp_mode:
    bl      rmdir_p
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

// rmdir_p(x23 = path): remove the directory, then each ancestor, stopping at the
// first that cannot be removed. x9 = end index (survives strlen/rmdir).
rmdir_p:
    stp     x29, x30, [sp, #-16]!
    mov     x0, x23
    bl      uolt_strlen
    mov     x9, x0                      // e = length
.Lrp_trail:
    cbz     x9, .Lrp_done
    sub     x10, x9, #1
    ldrb    w11, [x23, x10]
    cmp     w11, #'/'
    b.ne    .Lrp_rm
    sub     x9, x9, #1
    b       .Lrp_trail
.Lrp_rm:
    strb    wzr, [x23, x9]              // terminate at e
    mov     x0, x23
    bl      uolt_rmdir
    cmp     x0, #0
    b.mi    .Lrp_err
.Lrp_comp:
    cbz     x9, .Lrp_done
    sub     x10, x9, #1
    ldrb    w11, [x23, x10]
    cmp     w11, #'/'
    b.eq    .Lrp_sep
    sub     x9, x9, #1
    b       .Lrp_comp
.Lrp_sep:
    cbz     x9, .Lrp_done
    sub     x10, x9, #1
    ldrb    w11, [x23, x10]
    cmp     w11, #'/'
    b.ne    .Lrp_rm                     // parent found -> remove it
    sub     x9, x9, #1
    b       .Lrp_sep
.Lrp_err:
    ldp     x29, x30, [sp], #16
    b       diag
.Lrp_done:
    ldp     x29, x30, [sp], #16
    ret

// diag(x23 = path): "uolt-rmdir: <path>: cannot remove directory" -> stderr, status 1.
diag:
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

err_usage: .asciz "uolt-rmdir: usage: rmdir [-p] dir...\n"
err_pre:   .asciz "uolt-rmdir: "
err_suf:   .asciz ": cannot remove directory\n"
