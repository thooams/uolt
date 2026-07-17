// src/cat/arm64/cat.S - uolt-cat: the POSIX `cat` utility (aarch64).
//
// Concatenates file operands to stdout, in order; no operands (or "-") copies
// stdin. Fixed-size blocks through one stack buffer (no heap, Principle IV). -u
// accepted and ignored (output is already unbuffered). A file that cannot be
// opened -> stderr diagnostic, exit status 1, remaining operands still processed.
// Mirrors the x86_64 body.
//
// Callee-saved roles: x19 = current operand / open fd, x20 = buffer base,
//   x21 = accumulated exit status, x22 = operand count, x23 = &argv walk. The
//   leaf syscalls touch only x0/x8, so x9/x10 survive the write-drain loop.

#include "uolt.inc"

.set STDIN,    0
.set STDOUT,   1
.set STDERR,   2
.set O_RDONLY, 0
.set BUFSZ,    65536

.text
.globl uolt_main
uolt_main:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    str     x23, [sp, #48]
    sub     sp, sp, #BUFSZ
    mov     x20, sp                     // buffer base

    mov     x22, x0                     // argc
    mov     x23, x1                     // argv
    mov     x21, #0                     // exit status 0
    add     x23, x23, #8                // &argv[1]
    sub     x22, x22, #1                // operand count

    cbz     x22, .Lstdin_only

.Lloop:
    cbz     x22, .Lfinish
    ldr     x19, [x23]                  // current operand string
    ldrb    w9, [x19]
    cmp     w9, #'-'
    b.ne    .Lopen_file
    ldrb    w9, [x19, #1]
    cbz     w9, .Lstdin_operand         // exactly "-" -> stdin
    cmp     w9, #'u'
    b.ne    .Lopen_file
    ldrb    w9, [x19, #2]
    cbnz    w9, .Lopen_file
    add     x23, x23, #8                // "-u": ignore
    sub     x22, x22, #1
    b       .Lloop

.Lstdin_operand:
    mov     x19, #STDIN
    bl      cat_fd
    b       .Lnext

.Lopen_file:
    mov     x0, x19                     // path
    mov     x1, #O_RDONLY
    mov     x2, #0
    bl      uolt_open
    cmp     x0, #0
    b.mi    .Lopen_error
    mov     x19, x0                     // fd
    bl      cat_fd
    mov     x0, x19
    bl      uolt_close
    b       .Lnext

.Lopen_error:
    mov     x21, #1                     // failure; keep going
    adr     x0, err_pre
    bl      err_puts
    mov     x0, x19
    bl      err_puts
    adr     x0, err_suf
    bl      err_puts

.Lnext:
    add     x23, x23, #8
    sub     x22, x22, #1
    b       .Lloop

.Lstdin_only:
    mov     x19, #STDIN
    bl      cat_fd

.Lfinish:
    mov     x0, x21
    add     sp, sp, #BUFSZ
    ldr     x23, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret

// cat_fd: copy everything from descriptor x19 to stdout. x20 = buffer base; sets
// x21 = 1 on a read/write error. x9/x10 survive the write drain (kernel preserves
// them across the syscall wrapper). Saves lr (calls read/write).
cat_fd:
    stp     x29, x30, [sp, #-16]!
1:
    mov     x0, x19                     // read(fd, buf, BUFSZ)
    mov     x1, x20
    mov     x2, #BUFSZ
    bl      uolt_read
    cmp     x0, #0
    b.eq    3f                          // 0 -> EOF
    b.mi    2f                          // < 0 -> read error
    mov     x9, x0                      // bytes remaining
    mov     x10, x20                    // position
4:
    mov     x0, #STDOUT
    mov     x1, x10
    mov     x2, x9
    bl      uolt_write
    cmp     x0, #0
    b.mi    2f                          // write error
    add     x10, x10, x0
    subs    x9, x9, x0
    b.ne    4b
    b       1b
2:
    mov     x21, #1
3:
    ldp     x29, x30, [sp], #16
    ret

// err_puts(x0 = ASCIZ) -> stderr; length via strlen. Saves lr.
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

err_pre: .asciz "uolt-cat: "
err_suf: .asciz ": cannot open\n"
