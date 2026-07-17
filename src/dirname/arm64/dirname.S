// src/dirname/arm64/dirname.S - uolt-dirname: the POSIX `dirname` utility (aarch64).
//
// dirname string: prints the directory part of `string` plus a newline. Trailing
// '/' stripped; no '/' left yields "."; the separating '/' before the last
// component (and repeats) removed, and if nothing remains the result is "/".
// Pure string work on the argv operand (Principle IV). Mirrors the x86_64 body.
//
// Register roles (callee-saved):
//   x19 = string operand, x21 = end index after stripping trailing slashes,
//   x20 = working index (last-slash search, then dir length)

#include "uolt.inc"

.set STDOUT, 1
.set STDERR, 2

.text
.globl uolt_main
uolt_main:
    stp     x19, x20, [sp, #-32]!
    stp     x21, x30, [sp, #16]

    cmp     x0, #2
    b.lt    .Lmissing
    ldr     x19, [x1, #8]               // string (extra operands ignored)

    mov     x0, x19
    bl      uolt_strlen
    cbz     x0, .Ldot                   // empty string -> "."
    mov     x21, x0                     // e = len
.Lstrip:
    cbz     x21, .Lroot                 // all slashes -> "/"
    sub     x9, x21, #1
    ldrb    w2, [x19, x9]
    cmp     w2, #'/'
    b.ne    .Lstripped
    sub     x21, x21, #1
    b       .Lstrip
.Lstripped:
    mov     x20, x21                    // find the last '/' in s[0, e)
.Lfindp:
    cbz     x20, .Ldot                  // no '/' -> "."
    sub     x9, x20, #1
    ldrb    w2, [x19, x9]
    cmp     w2, #'/'
    b.eq    .Lstripd
    sub     x20, x20, #1
    b       .Lfindp
.Lstripd:
    // x20 points just past the last '/'. Strip that separator and any repeats;
    // the remainder [0, x20) is the directory (or "/" if it strips to nothing).
    cbz     x20, .Lroot
    sub     x9, x20, #1
    ldrb    w2, [x19, x9]
    cmp     w2, #'/'
    b.ne    .Lemit_dir
    sub     x20, x20, #1
    b       .Lstripd
.Lemit_dir:
    mov     x0, #STDOUT
    mov     x1, x19
    mov     x2, x20                     // directory length
    bl      uolt_write
    b       .Lemit_nl
.Ldot:
    mov     x0, #STDOUT
    adr     x1, dot_char
    mov     x2, #1
    bl      uolt_write
    b       .Lemit_nl
.Lroot:
    mov     x0, #STDOUT
    adr     x1, slash
    mov     x2, #1
    bl      uolt_write
.Lemit_nl:
    mov     x0, #STDOUT
    adr     x1, nl_char
    mov     x2, #1
    bl      uolt_write
    mov     x0, #0
    b       .Lret

.Lmissing:
    adr     x0, err_missing
    bl      err_puts
    mov     x0, #1
.Lret:
    ldp     x21, x30, [sp, #16]
    ldp     x19, x20, [sp], #32
    ret

// err_puts(x0 = ASCIZ) -> stderr; length via strlen. Saves lr (calls strlen).
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

dot_char:    .byte  '.'
slash:       .byte  '/'
nl_char:     .byte  0x0a
err_missing: .asciz "uolt-dirname: missing operand\n"
