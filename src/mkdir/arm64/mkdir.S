// src/mkdir/arm64/mkdir.S - the POSIX `mkdir` utility (aarch64).
//
// mkdir [-p] [-m MODE] dir...: create each directory. -p creates parents and
// tolerates an existing target; -m sets an exact octal mode (chmod after create,
// umask not applied) on the target. A failure -> stderr diagnostic, exit 1,
// remaining operands still processed. No heap (Principle IV): the -p walk edits
// the operand string in place. Mirrors the x86_64 body.
//
// Callee-saved roles: x19 = operand count, x20 = &argv walk, x21 = exit status,
//   x22 = -p flag, x23 = current path. Locals off x29.

#include "uolt.inc"

.set STDERR, 2
.set MODE,   0777
.set EEXIST, 17
.set LOC_MODE, 48
.set LOC_HASM, 56

.text
.globl uolt_main
uolt_main:
    sub     sp, sp, #64
    mov     x29, sp
    stp     x19, x20, [sp, #0]
    stp     x21, x22, [sp, #16]
    stp     x23, x30, [sp, #32]

    sub     x19, x0, #1
    add     x20, x1, #8
    mov     x21, #0
    mov     x22, #0                     // -p flag
    mov     x9, #MODE
    str     x9, [x29, #LOC_MODE]
    str     xzr, [x29, #LOC_HASM]
.Lopt:
    cbz     x19, .Lafter
    ldr     x23, [x20]
    ldrb    w9, [x23]
    cmp     w9, #'-'
    b.ne    .Lafter
    ldrb    w9, [x23, #1]
    cbz     w9, .Lafter                 // "-" -> a directory named "-"
    cmp     w9, #'p'
    b.ne    1f
    ldrb    w9, [x23, #2]
    cbnz    w9, 1f
    mov     x22, #1                     // -p
    add     x20, x20, #8
    sub     x19, x19, #1
    b       .Lopt
1:
    ldrb    w9, [x23, #1]
    cmp     w9, #'m'
    b.ne    2f
    add     x0, x23, #2                 // "-mMODE" attached, or "-m" then next arg
    ldrb    w9, [x0]
    cbnz    w9, .Lhave_mode
    add     x20, x20, #8
    sub     x19, x19, #1
    cbz     x19, .Lusage
    ldr     x0, [x20]
.Lhave_mode:
    bl      parse_octal                 // x0 = value, x1 = 0 ok / 1 error
    cbnz    x1, .Lusage
    str     x0, [x29, #LOC_MODE]
    mov     x9, #1
    str     x9, [x29, #LOC_HASM]
    add     x20, x20, #8
    sub     x19, x19, #1
    b       .Lopt
2:
    ldrb    w9, [x23, #1]
    cmp     w9, #'-'
    b.ne    .Lafter
    ldrb    w9, [x23, #2]
    cbnz    w9, .Lafter
    add     x20, x20, #8                // "--"
    sub     x19, x19, #1
.Lafter:
    cbz     x19, .Lusage
.Lloop:
    cbz     x19, .Lfin
    ldr     x23, [x20]
    cbnz    x22, .Lp_mode
    mov     x0, x23                     // plain mkdir
    ldr     x1, [x29, #LOC_MODE]
    bl      uolt_mkdir
    cmp     x0, #0
    b.mi    1f
    bl      apply_mode
    b       .Lnext
1:
    bl      diag
    b       .Lnext
.Lp_mode:
    bl      mkdir_p
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
    ldp     x19, x20, [sp, #0]
    ldp     x21, x22, [sp, #16]
    ldp     x23, x30, [sp, #32]
    add     sp, sp, #64
    ret

// mkdir_p(x23 = path): create every prefix directory (ignoring errors), then the
// full path. x9 = walk index (survives uolt_mkdir).
mkdir_p:
    stp     x29, x30, [sp, #-16]!
    mov     x9, #0
.Lmp_loop:
    ldrb    w10, [x23, x9]
    cbz     w10, .Lmp_final
    cmp     w10, #'/'
    b.ne    .Lmp_next
    cbz     x9, .Lmp_next               // leading slash: no empty prefix
    sub     x11, x9, #1
    ldrb    w10, [x23, x11]
    cmp     w10, #'/'
    b.eq    .Lmp_next                   // collapse repeated slashes
    strb    wzr, [x23, x9]              // terminate the prefix
    mov     x0, x23
    mov     x1, #MODE
    bl      uolt_mkdir                  // ignore result (EEXIST is fine)
    mov     w10, #'/'
    strb    w10, [x23, x9]              // restore
.Lmp_next:
    add     x9, x9, #1
    b       .Lmp_loop
.Lmp_final:
    mov     x0, x23
    ldr     x1, [x29, #LOC_MODE]
    bl      uolt_mkdir
    cmp     x0, #0
    b.ge    .Lmp_created
    cmn     x0, #EEXIST                 // x0 == -EEXIST ?
    b.eq    .Lmp_done
    ldp     x29, x30, [sp], #16
    b       diag
.Lmp_created:
    ldp     x29, x30, [sp], #16
    b       apply_mode
.Lmp_done:
    ldp     x29, x30, [sp], #16
    ret

// apply_mode(x23 = path): with -m, chmod the path to the exact mode.
apply_mode:
    ldr     x9, [x29, #LOC_HASM]
    cbz     x9, 1f
    stp     x29, x30, [sp, #-16]!
    mov     x0, x23
    ldr     x1, [x29, #LOC_MODE]
    bl      uolt_chmod
    ldp     x29, x30, [sp], #16
1:
    ret

// parse_octal(x0 = ASCIZ) -> x0 = value, x1 = 0 ok / 1 error. Leaf.
parse_octal:
    mov     x2, x0
    mov     x0, #0
    mov     x3, #0                      // digit-seen
    ldrb    w4, [x2]
    cbz     w4, .Lpo_err
.Lpo:
    ldrb    w4, [x2]
    cbz     w4, .Lpo_done
    sub     w4, w4, #'0'
    cmp     w4, #7
    b.hi    .Lpo_err
    lsl     x0, x0, #3
    add     x0, x0, w4, uxtw
    mov     x3, #1
    add     x2, x2, #1
    b       .Lpo
.Lpo_done:
    cbz     x3, .Lpo_err
    mov     x1, #0
    ret
.Lpo_err:
    mov     x1, #1
    ret

// diag(x23 = path): "uolt-mkdir: <path>: cannot create directory" -> stderr, status 1.
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

err_usage: .asciz "uolt-mkdir: usage: mkdir [-p] [-m MODE] dir...\n"
err_pre:   .asciz "uolt-mkdir: "
err_suf:   .asciz ": cannot create directory\n"
