// src/pwd/arm64/pwd.S - uolt-pwd: the POSIX `pwd` utility (aarch64).
//
// Prints the absolute pathname of the current working directory (physical, like
// `pwd -P`) followed by a newline, and exits 0. Options and arguments ignored in
// v1. The cwd is fetched into a stack buffer (no heap, Principle IV) via
// uolt_getcwd. Mirrors the x86_64 body.

#include "uolt.inc"

.set STDOUT, 1
.set BUFSZ,  4096               // >= PATH_MAX

.text
.globl uolt_main
uolt_main:
    stp     x29, x30, [sp, #-16]!       // save lr across the calls
    sub     sp, sp, #BUFSZ              // stack buffer for the path

    mov     x0, sp                      // buf
    mov     x1, #BUFSZ                  // size
    bl      uolt_getcwd
    cmp     x0, #0
    b.mi    .Lerror                     // negative -> failure

    mov     x0, sp                      // strlen(buf)
    bl      uolt_strlen
    mov     x2, x0                      // length
    mov     x1, sp                      // buf
    mov     x0, #STDOUT
    bl      uolt_write

    mov     x0, #STDOUT                 // trailing newline
    adr     x1, nl_char
    mov     x2, #1
    bl      uolt_write

    mov     x0, #0                      // exit status 0
    b       .Ldone
.Lerror:
    mov     x0, #1                      // exit status 1 on getcwd failure
.Ldone:
    add     sp, sp, #BUFSZ
    ldp     x29, x30, [sp], #16
    ret

nl_char: .byte 0x0a
