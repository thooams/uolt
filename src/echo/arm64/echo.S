// src/echo/arm64/echo.S - uolt-echo: the POSIX `echo` utility (aarch64).
//
// Writes its arguments to stdout, separated by single spaces, followed by a
// newline. A leading "-n" suppresses the trailing newline (BSD / common
// behavior; no GNU "-e" escape processing - POSIX, not GNU, Principle VIII).
// Mirrors the x86_64 algorithm exactly.
//
// Called as uolt_main(argc in x0, argv in x1) by the per-arch entry shim.
// No heap (Principle IV): output is emitted with one write per piece (arg,
// separator, newline).
//
// Register roles across the loop (all callee-saved, so they survive the syscalls
// made by uolt_write / uolt_strlen; lr is saved in the frame):
//   x19 = remaining argument count
//   x20 = pointer to the current argv entry
//   x21 = suppress-newline flag (0 = print newline, 1 = -n given)
//   x22 = separator-needed flag (0 before first arg, 1 afterwards)
//   x23 = scratch pointer to the current argument string

#include "uolt.inc"

.set STDOUT, 1

.text
.globl uolt_main
uolt_main:
    stp     x19, x20, [sp, #-48]!       // frame: save callee-saved regs + lr
    stp     x21, x22, [sp, #16]
    stp     x23, x30, [sp, #32]

    mov     x19, x0                     // argc
    add     x20, x1, #8                 // &argv[1] (skip argv[0], the program name)
    sub     x19, x19, #1                // count of user arguments
    mov     x21, #0                     // print newline by default
    mov     x22, #0                     // no separator before the first argument

    // Recognize a single leading "-n".
    cbz     x19, .Lemit_end
    ldr     x23, [x20]                  // argv[1]
    ldrb    w0, [x23]
    cmp     w0, #'-'
    b.ne    .Lloop
    ldrb    w0, [x23, #1]
    cmp     w0, #'n'
    b.ne    .Lloop
    ldrb    w0, [x23, #2]
    cbnz    w0, .Lloop
    mov     x21, #1                     // -n: suppress trailing newline
    add     x20, x20, #8
    sub     x19, x19, #1

.Lloop:
    cbz     x19, .Lemit_end

    cbz     x22, .Lno_sep               // need a space separator?
    mov     x0, STDOUT
    adr     x1, sp_char
    mov     x2, #1
    bl      uolt_write
.Lno_sep:
    mov     x22, #1

    ldr     x23, [x20]                  // current argument string
    mov     x0, x23
    bl      uolt_strlen                 // x0 = length
    mov     x2, x0
    mov     x1, x23
    mov     x0, STDOUT
    bl      uolt_write

    add     x20, x20, #8
    sub     x19, x19, #1
    b       .Lloop

.Lemit_end:
    cbnz    x21, .Ldone                 // -n given? then no newline
    mov     x0, STDOUT
    adr     x1, nl_char
    mov     x2, #1
    bl      uolt_write
.Ldone:
    mov     x0, #0                      // exit status 0
    ldp     x23, x30, [sp, #32]
    ldp     x21, x22, [sp, #16]
    ldp     x19, x20, [sp], #48
    ret

// Single-byte constants kept in the text segment (the Linux link script folds
// rodata into .text). Reached only via adr, never executed.
sp_char: .byte 0x20                     // ' '
nl_char: .byte 0x0a                     // '\n'
