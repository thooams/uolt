// src/tee/arm64/tee.S - the POSIX `tee` utility, aarch64.
//
// tee [-a] [file...]: copy standard input to standard output and to each named
// file. With -a the files are appended to instead of truncated. Data flows
// through one 64 KB stack buffer (no heap, Principle IV); each read block is
// drained to stdout and to every open output file. Up to MAXFILES files; a file
// that cannot be opened yields a diagnostic and sets the exit status to 1 but does
// not stop the copy to the others. Mirrors the x86_64 body.
//
// Callee-saved roles: x19 = buffer base; x20 = fd array base; x21 = exit status;
//   x22 = number of open fds; x23 = operand count then fd index; x24 = current fd
//   / path; x25 = write ptr; x26 = write remaining. Locals off x29.

#include "uolt.inc"

.set STDIN,    0
.set STDOUT,   1
.set STDERR,   2
.set MODE,     0666
.set BUFSZ,    65536
.set MAXFILES, 64

.set LOC_APP,  72
.set LOC_ARGV, 80
.set LOC_BLEN, 88

.text
.globl uolt_main
uolt_main:
    sub     sp, sp, #96
    mov     x29, sp
    stp     x19, x20, [sp, #0]
    stp     x21, x22, [sp, #16]
    stp     x23, x24, [sp, #32]
    stp     x25, x26, [sp, #48]
    str     x30, [sp, #64]
    sub     sp, sp, #65536             // BUFSZ
    sub     sp, sp, #544              // MAXFILES*8 + 32
    mov     x19, sp                    // buffer
    add     x20, x19, #BUFSZ           // fd array
    mov     x21, #0                    // exit status
    mov     x22, #0                    // open fd count
    str     xzr, [x29, #LOC_APP]
    sub     x23, x0, #1                // operand count
    add     x9, x1, #8
    str     x9, [x29, #LOC_ARGV]
.opt:
    cbz     x23, .open_files
    ldr     x9, [x29, #LOC_ARGV]
    ldr     x9, [x9]
    ldrb    w10, [x9]
    cmp     w10, #'-'
    b.ne    .open_files
    ldrb    w10, [x9, #1]
    cbz     w10, .open_files           // "-" is a file operand
    cmp     w10, #'a'
    b.ne    .opt_ddash
    ldrb    w10, [x9, #2]
    cbnz    w10, .opt_ddash
    mov     x10, #1                    // -a
    str     x10, [x29, #LOC_APP]
    ldr     x10, [x29, #LOC_ARGV]
    add     x10, x10, #8
    str     x10, [x29, #LOC_ARGV]
    sub     x23, x23, #1
    b       .opt
.opt_ddash:
    ldrb    w10, [x9, #1]
    cmp     w10, #'-'
    b.ne    .open_files
    ldrb    w10, [x9, #2]
    cbnz    w10, .open_files
    ldr     x10, [x29, #LOC_ARGV]
    add     x10, x10, #8
    str     x10, [x29, #LOC_ARGV]
    sub     x23, x23, #1
.open_files:
    cbz     x23, .copy
    cmp     x22, #MAXFILES
    b.hs    .copy
    ldr     x9, [x29, #LOC_ARGV]
    ldr     x24, [x9]                  // path
    mov     x0, x24
    mov     x1, #MODE
    ldr     x10, [x29, #LOC_APP]
    cbz     x10, .of_trunc
    bl      uolt_openapp
    b       .of_check
.of_trunc:
    bl      uolt_opendst
.of_check:
    cmp     x0, #0
    b.mi    .of_err
    str     x0, [x20, x22, lsl #3]     // store the fd
    add     x22, x22, #1
    b       .of_next
.of_err:
    mov     x21, #1
    adr     x0, err_pre
    bl      err_puts
    mov     x0, x24
    bl      err_puts
    adr     x0, err_suf
    bl      err_puts
.of_next:
    ldr     x10, [x29, #LOC_ARGV]
    add     x10, x10, #8
    str     x10, [x29, #LOC_ARGV]
    sub     x23, x23, #1
    b       .open_files

.copy:
    mov     x0, #STDIN
    mov     x1, x19
    mov     x2, #BUFSZ
    bl      uolt_read
    cmp     x0, #0
    b.le    .done                      // EOF (0) or error (<0)
    str     x0, [x29, #LOC_BLEN]       // block length
    mov     x23, #-1                   // fd index: -1 = stdout, 0.. = files
.cp_out:
    cmp     x23, x22
    b.ge    .copy                      // wrote stdout + all files: read again
    cmp     x23, #0
    b.mi    .cp_stdout
    ldr     x24, [x20, x23, lsl #3]    // file fd
    b       .cp_setup
.cp_stdout:
    mov     x24, #STDOUT
.cp_setup:
    ldr     x26, [x29, #LOC_BLEN]      // remaining bytes for this fd
    mov     x25, x19                   // ptr
.cp_w:
    cbz     x26, .cp_done_fd
    mov     x0, x24
    mov     x1, x25
    mov     x2, x26
    bl      uolt_write
    cmp     x0, #0
    b.mi    .cp_werr
    add     x25, x25, x0
    sub     x26, x26, x0
    b       .cp_w
.cp_werr:
    mov     x21, #1
.cp_done_fd:
    add     x23, x23, #1
    b       .cp_out

.done:
    mov     x23, #0                    // close all output files
.dc:
    cmp     x23, x22
    b.hs    .fin
    ldr     x0, [x20, x23, lsl #3]
    bl      uolt_close
    add     x23, x23, #1
    b       .dc
.fin:
    mov     x0, x21
    mov     sp, x29
    ldp     x19, x20, [sp, #0]
    ldp     x21, x22, [sp, #16]
    ldp     x23, x24, [sp, #32]
    ldp     x25, x26, [sp, #48]
    ldr     x30, [sp, #64]
    add     sp, sp, #96
    ret

// err_puts(x0 = ASCIZ) -> stderr. Saves lr.
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

err_pre: .asciz "uolt-tee: "
err_suf: .asciz ": cannot open\n"
