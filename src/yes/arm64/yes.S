// src/yes/arm64/yes.S - uolt-yes: the POSIX `yes` utility (aarch64).
//
// Repeatedly writes a line to stdout until the write fails (reader closed the
// pipe -> SIGPIPE or -EPIPE, exit 1). The line is the operands joined by spaces,
// or "y", followed by a newline. For throughput the line is replicated to fill a
// 64 KB stack buffer (no heap, Principle IV) and the whole buffer is written each
// iteration; a line longer than the buffer falls back to a piecewise emit.
// Mirrors the x86_64 body (x86 `rep movsb` becomes a byte-copy loop). The leaf
// syscalls only touch x0/x1/x2/x8, so x9..x15 persist across the libuolt calls.
//
// Callee-saved roles: x19 = arg count / later fill length, x20 = &argv[1] / later
//   running offset, x21 = line length L, x22 = 64 KB buffer base.

#include "uolt.inc"

.set STDOUT, 1
.set BUFSZ,  65536

.text
.globl uolt_main
uolt_main:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    sub     sp, sp, #BUFSZ
    mov     x22, sp                     // buffer base

    sub     x19, x0, #1                 // argument count (argc - 1)
    add     x20, x1, #8                 // &argv[1]

    cbnz    x19, .Lhave_args
    // No operands: the line is "y\n".
    mov     w9, #'y'
    strb    w9, [x22]
    mov     w9, #0x0a
    strb    w9, [x22, #1]
    mov     x21, #2
    b       .Lbatch

.Lhave_args:
    // L = sum(strlen(arg)) + count (separators + trailing newline).
    mov     x23, #0                     // sum
    mov     x24, #0                     // i
.Lsum_loop:
    cmp     x24, x19
    b.hs    .Lsum_done
    ldr     x0, [x20, x24, lsl #3]
    bl      uolt_strlen
    add     x23, x23, x0
    add     x24, x24, #1
    b       .Lsum_loop
.Lsum_done:
    add     x23, x23, x19
    mov     x21, x23                    // L
    mov     x9, #BUFSZ
    cmp     x21, x9
    b.hi    .Lfallback                  // one line does not fit -> piecewise path

    // Build one copy of the line at the buffer start.
    mov     x9, #0                      // pos
    mov     x10, #0                     // i
.Lbuild:
    cmp     x10, x19
    b.hs    .Lbuild_nl
    cbz     x10, .Lno_space
    mov     w11, #' '
    strb    w11, [x22, x9]
    add     x9, x9, #1
.Lno_space:
    ldr     x0, [x20, x10, lsl #3]
    bl      uolt_strlen                 // x0 = len (x9,x10 survive)
    ldr     x1, [x20, x10, lsl #3]      // src
    add     x2, x22, x9                 // dst
    add     x9, x9, x0                  // pos += len
    mov     x3, x0                      // count
.Lcpy1:
    cbz     x3, .Lcpy1_done
    ldrb    w11, [x1], #1
    strb    w11, [x2], #1
    sub     x3, x3, #1
    b       .Lcpy1
.Lcpy1_done:
    add     x10, x10, #1
    b       .Lbuild
.Lbuild_nl:
    mov     w11, #0x0a
    strb    w11, [x22, x9]              // x9 now equals L

.Lbatch:
    // fill = floor(BUFSZ / L) * L : whole copies only.
    mov     x9, #BUFSZ
    udiv    x10, x9, x21
    mul     x10, x10, x21
    mov     x19, x10                    // fill
    mov     x20, x21                    // copied = L
.Lrep_fill:
    cmp     x20, x19
    b.hs    .Lrep_done
    mov     x3, x20                     // chunk = min(copied, fill - copied)
    sub     x4, x19, x20
    cmp     x3, x4
    b.ls    1f
    mov     x3, x4
1:
    mov     x1, x22                     // src
    add     x2, x22, x20                // dst
    add     x20, x20, x3                // copied += chunk
.Lcpy2:
    cbz     x3, .Lcpy2_done
    ldrb    w11, [x1], #1
    strb    w11, [x2], #1
    sub     x3, x3, #1
    b       .Lcpy2
.Lcpy2_done:
    b       .Lrep_fill
.Lrep_done:

    // Write the full buffer forever; drain short writes to keep line alignment.
.Lwloop:
    mov     x20, #0                     // offset
.Lwdrain:
    cmp     x20, x19
    b.hs    .Lwloop
    mov     x0, #STDOUT
    add     x1, x22, x20
    sub     x2, x19, x20
    bl      uolt_write
    cmp     x0, #0
    b.le    .Lwexit                     // <= 0: closed / error
    add     x20, x20, x0
    b       .Lwdrain

// Piecewise path for a line longer than the buffer: emit args + spaces + newline
// straight from argv every iteration. Here x19=count, x20=&argv[1] still hold.
.Lfallback:
.Lfb_loop:
    mov     x10, #0                     // i
.Lfb_arg:
    cmp     x10, x19
    b.hs    .Lfb_nl
    cbz     x10, .Lfb_nosp
    mov     w11, #' '
    strb    w11, [x22]
    mov     x0, #STDOUT
    mov     x1, x22
    mov     x2, #1
    bl      uolt_write
    cmp     x0, #0
    b.le    .Lwexit
.Lfb_nosp:
    ldr     x0, [x20, x10, lsl #3]
    bl      uolt_strlen
    mov     x2, x0
    ldr     x1, [x20, x10, lsl #3]
    mov     x0, #STDOUT
    bl      uolt_write
    cmp     x0, #0
    b.le    .Lwexit
    add     x10, x10, #1
    b       .Lfb_arg
.Lfb_nl:
    mov     w11, #0x0a
    strb    w11, [x22]
    mov     x0, #STDOUT
    mov     x1, x22
    mov     x2, #1
    bl      uolt_write
    cmp     x0, #0
    b.le    .Lwexit
    b       .Lfb_loop

.Lwexit:
    mov     x0, #1                      // write failed (pipe closed) -> exit 1
    add     sp, sp, #BUFSZ
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret
