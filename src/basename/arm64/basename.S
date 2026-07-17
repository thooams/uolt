// src/basename/arm64/basename.S - uolt-basename: the POSIX `basename` utility (aarch64).
//
// basename string [suffix]: prints the final path component of `string` plus a
// newline. Trailing '/' removed first; all-slashes becomes "/"; empty string
// prints an empty line. A `suffix` that the component ends with (but is not equal
// to) is removed. Pure string work on the argv operands - no files, no buffer
// (Principle IV). Mirrors the x86_64 body.
//
// Register roles (callee-saved, survive the libuolt calls):
//   x19 = string operand, x20 = suffix (0 if none)
//   x21 = end index e, x22 = component start b, x23 = component length

#include "uolt.inc"

.set STDOUT, 1
.set STDERR, 2

.text
.globl uolt_main
uolt_main:
    stp     x19, x20, [sp, #-48]!
    stp     x21, x22, [sp, #16]
    stp     x23, x30, [sp, #32]

    cmp     x0, #2
    b.lt    .Lmissing                   // need at least one operand
    ldr     x19, [x1, #8]               // string
    mov     x20, #0                     // suffix = none
    cmp     x0, #3
    b.lt    1f
    ldr     x20, [x1, #16]              // suffix (extra operands ignored)
1:
    mov     x0, x19
    bl      uolt_strlen
    cbz     x0, .Lemit_nl               // empty string -> empty line
    mov     x21, x0                     // e = len
.Lstrip:
    cbz     x21, .Lall_slash
    sub     x9, x21, #1
    ldrb    w2, [x19, x9]
    cmp     w2, #'/'
    b.ne    .Lstripped
    sub     x21, x21, #1                // drop a trailing slash
    b       .Lstrip
.Lall_slash:
    mov     x0, #STDOUT                 // whole string was slashes -> "/"
    adr     x1, slash
    mov     x2, #1
    bl      uolt_write
    b       .Lemit_nl
.Lstripped:
    mov     x22, x21                    // find the byte after the last '/'
.Lfindb:
    cbz     x22, .Lhave_b
    sub     x9, x22, #1
    ldrb    w2, [x19, x9]
    cmp     w2, #'/'
    b.eq    .Lhave_b
    sub     x22, x22, #1
    b       .Lfindb
.Lhave_b:
    sub     x23, x21, x22               // component length = e - b

    cbz     x20, .Lemit                 // suffix given?
    mov     x0, x20
    bl      uolt_strlen                 // x0 = suffix length
    cbz     x0, .Lemit
    cmp     x0, x23
    b.ge    .Lemit                      // suffix >= component -> keep whole
    // Compare the component's tail with the suffix.
    add     x3, x19, x21
    sub     x3, x3, x0                  // tail start = s + e - suffixlen
    mov     x4, x20                     // suffix ptr
    mov     x5, x0                      // count
.Lcmpl:
    cbz     x5, .Lsuffix_match
    ldrb    w6, [x3]
    ldrb    w7, [x4]
    cmp     w6, w7
    b.ne    .Lemit                      // mismatch -> keep whole
    add     x3, x3, #1
    add     x4, x4, #1
    sub     x5, x5, #1
    b       .Lcmpl
.Lsuffix_match:
    sub     x23, x23, x0                // strip the suffix
.Lemit:
    mov     x0, #STDOUT                 // write component [b, b+len)
    add     x1, x19, x22
    mov     x2, x23
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
    ldp     x23, x30, [sp, #32]
    ldp     x21, x22, [sp, #16]
    ldp     x19, x20, [sp], #48
    ret

// err_puts(x0 = ASCIZ) -> stderr; length via strlen (no magic numbers). Saves lr
// because it calls uolt_strlen before writing.
err_puts:
    stp     x29, x30, [sp, #-16]!
    mov     x3, x0                      // save ptr (survives strlen)
    bl      uolt_strlen
    mov     x2, x0                      // length
    mov     x1, x3                      // buf
    mov     x0, #STDERR
    bl      uolt_write
    ldp     x29, x30, [sp], #16
    ret

slash:       .byte  '/'
nl_char:     .byte  0x0a
err_missing: .asciz "uolt-basename: missing operand\n"
