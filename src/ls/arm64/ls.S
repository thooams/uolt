// src/ls/arm64/ls.S - the `ls` utility (one entry per line), aarch64.
//
// ls [-a] [-1] [operand...]: list the entries of each directory operand (one name
// per line), or print the name of each file operand. No operand lists ".". -a
// includes dot-entries; -1 is the default. Entries are NOT sorted (no bounded,
// heap-free sort of an unbounded set); the differential test compares the set of
// names. Mirrors the x86_64 body.
//
// A directory is detected without stat by opening with O_DIRECTORY (opendir): it
// fails with ENOTDIR on a regular file (print its name) and ENOENT on a missing
// path (a diagnostic). One 32 KB stack buffer (no heap, Principle IV).
//
// Callee-saved: x19 = buffer; x20 = operand count; x21 = &argv walk; x22 = exit
//   status; x23 = current operand. Local off x29.

#include "uolt.inc"

.set STDOUT,   1
.set STDERR,   2
.set ENOTDIR,  20
.set BUFSZ,    32768

.set LOC_A, 56

.text
.globl uolt_main
uolt_main:
    sub     sp, sp, #64
    mov     x29, sp
    str     x30, [x29, #0]
    stp     x19, x20, [x29, #16]
    stp     x21, x22, [x29, #32]
    str     x23, [x29, #48]
    sub     sp, sp, #BUFSZ
    mov     x19, sp
    mov     x22, #0                    // exit status
    str     xzr, [x29, #LOC_A]
    sub     x20, x0, #1                // operand count
    add     x21, x1, #8                // &argv[1]
.opt:
    cbz     x20, .after
    ldr     x23, [x21]
    ldrb    w9, [x23]
    cmp     w9, #'-'
    b.ne    .after
    ldrb    w9, [x23, #1]
    cbz     w9, .after
    cmp     w9, #'-'
    b.eq    .ddash
    add     x3, x23, #1                // validate letters are a/1
    mov     x4, x3
.vl:
    ldrb    w9, [x3]
    cbz     w9, .apply
    cmp     w9, #'a'
    b.eq    .vl_ok
    cmp     w9, #'1'
    b.eq    .vl_ok
    b       .after                     // unknown -> operand
.vl_ok:
    add     x3, x3, #1
    b       .vl
.apply:
    mov     x3, x4
.apl:
    ldrb    w9, [x3]
    cbz     w9, .apd
    cmp     w9, #'a'
    b.ne    .apl_n
    mov     x10, #1
    str     x10, [x29, #LOC_A]
.apl_n:
    add     x3, x3, #1
    b       .apl
.apd:
    add     x21, x21, #8
    sub     x20, x20, #1
    b       .opt
.ddash:
    ldrb    w9, [x23, #2]
    cbnz    w9, .after
    add     x21, x21, #8
    sub     x20, x20, #1
.after:
    cbnz    x20, .oploop
    adr     x23, dot                   // no operand -> "."
    bl      list_one
    b       .fin
.oploop:
    cbz     x20, .fin
    ldr     x23, [x21]
    bl      list_one
    add     x21, x21, #8
    sub     x20, x20, #1
    b       .oploop

.fin:
    mov     x0, x22
    mov     sp, x29
    ldr     x30, [x29, #0]
    ldp     x19, x20, [x29, #16]
    ldp     x21, x22, [x29, #32]
    ldr     x23, [x29, #48]
    add     sp, sp, #64
    ret

// list_one(x23 = path): list a directory's entries, or print a file's name.
// x24 = fd, x25 = batch length, x26 = position in the batch.
list_one:
    sub     sp, sp, #48
    stp     x24, x25, [sp, #0]
    stp     x26, x30, [sp, #16]
    mov     x0, x23
    bl      uolt_opendir
    cmp     x0, #0
    b.mi    .lo_not_dir
    mov     x24, x0                    // fd
.lo_read:
    mov     x0, x24
    mov     x1, x19
    mov     x2, #BUFSZ
    bl      uolt_getdents
    cmp     x0, #0
    b.eq    .lo_done                   // end of directory
    b.mi    .lo_readerr
    mov     x25, x0                    // batch length
    mov     x26, #0
.lo_ent:
    cmp     x26, x25
    b.hs    .lo_read
    add     x10, x19, x26
    add     x10, x10, #DIRENT_NAME_OFF // entry name
    ldr     x11, [x29, #LOC_A]
    cbnz    x11, .lo_print
    ldrb    w11, [x10]
    cmp     w11, #'.'
    b.eq    .lo_next                   // hidden and -a not set
.lo_print:
    mov     x0, x10
    bl      put_name
.lo_next:
    add     x11, x19, x26
    ldrh    w12, [x11, #DIRENT_RECLEN_OFF]
    cbz     w12, .lo_read              // reclen 0 guard
    add     x26, x26, x12
    b       .lo_ent
.lo_not_dir:
    cmn     x0, #ENOTDIR
    b.ne    .lo_diag
    mov     x0, x23                    // it is a file: print its name
    bl      put_name
    b       .lo_ret
.lo_done:
    mov     x0, x24
    bl      uolt_close
    b       .lo_ret
.lo_readerr:
    mov     x0, x24
    bl      uolt_close
.lo_diag:
    mov     x22, #1
    adr     x0, err_pre
    bl      err_puts
    mov     x0, x23
    bl      err_puts
    adr     x0, err_suf
    bl      err_puts
.lo_ret:
    ldp     x24, x25, [sp, #0]
    ldp     x26, x30, [sp, #16]
    add     sp, sp, #48
    ret

// put_name(x0 = ASCIZ name): write the name and a newline to stdout.
put_name:
    stp     x29, x30, [sp, #-16]!
    mov     x3, x0
    bl      uolt_strlen
    mov     x2, x0
    mov     x1, x3
    mov     x0, #STDOUT
    bl      uolt_write
    mov     x0, #STDOUT
    adr     x1, nl_char
    mov     x2, #1
    bl      uolt_write
    ldp     x29, x30, [sp], #16
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

dot:       .asciz "."
nl_char:   .byte  0x0a
err_pre:   .asciz "uolt-ls: "
err_suf:   .asciz ": cannot access\n"
