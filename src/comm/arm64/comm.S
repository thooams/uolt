// src/comm/arm64/comm.S - the POSIX `comm` utility, aarch64.
//
// comm [-1] [-2] [-3] file1 file2: compare two sorted files line by line and
// write three tab-separated columns: lines only in file1, lines only in file2,
// and lines in both. -1/-2/-3 suppress the corresponding column; the tab
// indentation of a column is the number of non-suppressed columns before it.
//
// Both files are read fully into fixed buffers and split into line-pointer arrays
// on the stack (no heap, Principle IV; input beyond the buffer is dropped), then
// merged with a byte comparison. Mirrors the x86_64 body.
//
// Layout at x19: buf1[TBUF] buf2[TBUF] ptr1[MAXL*8] ptr2[MAXL*8]. Locals off x29.
// main: x20 = argc-1 then merge i; x21 = &argv walk then merge j; x22 = token.

#include "uolt.inc"

.set STDOUT, 1
.set STDERR, 2
.set O_RDONLY, 0
.set TBUF,   262144
.set MAXL,   32768

.set LOC_N1,   48
.set LOC_N2,   56
.set LOC_EN,   64
.set LOC_CH,   72

// Buffer offsets from x19.
.set OFF_BUF2, 262144                    // TBUF
.set OFF_PTR1, 524288                    // 2*TBUF
.set OFF_PTR2, 786432                    // 2*TBUF + MAXL*8

.text
.globl uolt_main
uolt_main:
    sub     sp, sp, #96
    mov     x29, sp
    stp     x19, x20, [sp, #0]
    stp     x21, x22, [sp, #16]
    str     x30, [sp, #32]
    sub     sp, sp, #1048576          // 2*TBUF + 2*MAXL*8
    sub     sp, sp, #96
    mov     x19, sp
    mov     x9, #7                    // all columns enabled
    str     x9, [x29, #LOC_EN]

    sub     x20, x0, #1                // argc - 1
    add     x21, x1, #8                // &argv[1]
.opt:
    cbz     x20, .after
    ldr     x22, [x21]
    ldrb    w9, [x22]
    cmp     w9, #'-'
    b.ne    .after
    ldrb    w9, [x22, #1]
    cbz     w9, .after
    cmp     w9, #'-'
    b.eq    .ddash
    add     x3, x22, #1               // combined flags, e.g. -12
.oflag:
    ldrb    w9, [x3]
    cbz     w9, .optnext
    cmp     w9, #'1'
    b.ne    .of2
    mov     x11, #1
    b       .ofclr
.of2:
    cmp     w9, #'2'
    b.ne    .of3
    mov     x11, #2
    b       .ofclr
.of3:
    cmp     w9, #'3'
    b.ne    .after                    // unknown flag letter -> stop
    mov     x11, #4
.ofclr:
    ldr     x10, [x29, #LOC_EN]
    bic     x10, x10, x11
    str     x10, [x29, #LOC_EN]
    add     x3, x3, #1
    b       .oflag
.optnext:
    add     x21, x21, #8
    sub     x20, x20, #1
    b       .opt
.ddash:
    ldrb    w9, [x22, #2]
    cbnz    w9, .after
    add     x21, x21, #8
    sub     x20, x20, #1
.after:
    cmp     x20, #2
    b.ne    .usage

    // read + split file1 -> ptr1, n1
    ldr     x0, [x21]
    mov     x1, x19                   // buf1
    bl      read_file
    cmp     x0, #0
    b.mi    .openerr
    mov     x1, x0                    // fill1
    mov     x0, x19
    add     x2, x19, #OFF_PTR1
    bl      split_lines
    str     x0, [x29, #LOC_N1]

    // read + split file2 -> ptr2, n2
    ldr     x0, [x21, #8]
    add     x1, x19, #OFF_BUF2
    bl      read_file
    cmp     x0, #0
    b.mi    .openerr2
    mov     x1, x0
    add     x0, x19, #OFF_BUF2
    add     x2, x19, #OFF_PTR2
    bl      split_lines
    str     x0, [x29, #LOC_N2]

    // merge
    mov     x20, #0                   // i (file1)
    mov     x21, #0                   // j (file2)
.merge:
    ldr     x9, [x29, #LOC_N1]
    cmp     x20, x9
    b.hs    .drain2
    ldr     x9, [x29, #LOC_N2]
    cmp     x21, x9
    b.hs    .drain1
    add     x9, x19, #OFF_PTR1
    ldr     x0, [x9, x20, lsl #3]     // line1[i]
    add     x9, x19, #OFF_PTR2
    ldr     x1, [x9, x21, lsl #3]     // line2[j]
    bl      line_cmp
    cmp     x0, #0
    b.mi    .only1
    b.gt    .only2
    add     x9, x19, #OFF_PTR1        // equal -> column 3 (both)
    ldr     x0, [x9, x20, lsl #3]
    mov     x1, #3
    bl      emit_col
    add     x20, x20, #1
    add     x21, x21, #1
    b       .merge
.only1:
    add     x9, x19, #OFF_PTR1
    ldr     x0, [x9, x20, lsl #3]
    mov     x1, #1
    bl      emit_col
    add     x20, x20, #1
    b       .merge
.only2:
    add     x9, x19, #OFF_PTR2
    ldr     x0, [x9, x21, lsl #3]
    mov     x1, #2
    bl      emit_col
    add     x21, x21, #1
    b       .merge
.drain1:
    ldr     x9, [x29, #LOC_N1]
    cmp     x20, x9
    b.hs    .fin
    add     x9, x19, #OFF_PTR1
    ldr     x0, [x9, x20, lsl #3]
    mov     x1, #1
    bl      emit_col
    add     x20, x20, #1
    b       .drain1
.drain2:
    ldr     x9, [x29, #LOC_N2]
    cmp     x21, x9
    b.hs    .fin
    add     x9, x19, #OFF_PTR2
    ldr     x0, [x9, x21, lsl #3]
    mov     x1, #2
    bl      emit_col
    add     x21, x21, #1
    b       .drain2
.fin:
    mov     x0, #0
    b       .ret
.openerr:
    ldr     x0, [x21]
    b       .diag
.openerr2:
    ldr     x0, [x21, #8]
.diag:
    mov     x22, x0                   // path (survives err_puts)
    adr     x0, err_pre
    bl      err_puts
    mov     x0, x22
    bl      err_puts
    adr     x0, err_suf
    bl      err_puts
    mov     x0, #1
    b       .ret
.usage:
    adr     x0, err_usage
    bl      err_puts
    mov     x0, #1
.ret:
    mov     sp, x29
    ldp     x19, x20, [sp, #0]
    ldp     x21, x22, [sp, #16]
    ldr     x30, [sp, #32]
    add     sp, sp, #96
    ret

// emit_col(x0 = line ptr, x1 = column 1/2/3): print the line in its column if
// enabled, prefixed by a tab per enabled column before it. Saves x20/x21/x22.
emit_col:
    sub     sp, sp, #48
    stp     x20, x21, [sp, #0]
    stp     x22, x30, [sp, #16]
    mov     x20, x0                   // line
    mov     x21, x1                   // column
    ldr     x9, [x29, #LOC_EN]
    sub     x10, x21, #1              // bit (col-1)
    lsr     x11, x9, x10
    tbz     x11, #0, .ec_ret          // column disabled
    mov     x22, #0                   // tab count
    tbz     x9, #0, .ec_t2            // col1 enabled?
    cmp     x21, #1
    b.le    .ec_t2
    add     x22, x22, #1
.ec_t2:
    tbz     x9, #1, .ec_tab           // col2 enabled?
    cmp     x21, #2
    b.le    .ec_tab
    add     x22, x22, #1
.ec_tab:
    cbz     x22, .ec_line
    mov     w9, #0x09
    strb    w9, [x29, #LOC_CH]
    mov     x0, #STDOUT
    add     x1, x29, #LOC_CH
    mov     x2, #1
    bl      uolt_write
    sub     x22, x22, #1
    b       .ec_tab
.ec_line:
    mov     x0, x20
    bl      uolt_strlen
    mov     x2, x0
    mov     x1, x20
    mov     x0, #STDOUT
    bl      uolt_write
    mov     w9, #0x0a
    strb    w9, [x29, #LOC_CH]
    mov     x0, #STDOUT
    add     x1, x29, #LOC_CH
    mov     x2, #1
    bl      uolt_write
.ec_ret:
    ldp     x20, x21, [sp, #0]
    ldp     x22, x30, [sp, #16]
    add     sp, sp, #48
    ret

// read_file(x0 = path, x1 = dest buffer) -> x0 = bytes read, or -1 on open error.
// Reads up to TBUF bytes. Saves x20/x21/x22.
read_file:
    sub     sp, sp, #48
    stp     x20, x21, [sp, #0]
    stp     x22, x30, [sp, #16]
    mov     x22, x1                   // dest
    mov     x1, #O_RDONLY
    mov     x2, #0
    bl      uolt_open
    cmp     x0, #0
    b.mi    .rf_err
    mov     x20, x0                   // fd
    mov     x21, #0                   // fill
.rf_read:
    mov     x2, #TBUF
    sub     x2, x2, x21
    cbz     x2, .rf_close
    mov     x0, x20
    add     x1, x22, x21
    bl      uolt_read
    cmp     x0, #0
    b.le    .rf_close
    add     x21, x21, x0
    b       .rf_read
.rf_close:
    mov     x0, x20
    bl      uolt_close
    mov     x0, x21
    b       .rf_out
.rf_err:
    mov     x0, #-1
.rf_out:
    ldp     x20, x21, [sp, #0]
    ldp     x22, x30, [sp, #16]
    add     sp, sp, #48
    ret

// split_lines(x0 = buf, x1 = length, x2 = ptr array) -> x0 = line count. Replaces
// each newline with NUL and records line starts. Leaf.
split_lines:
    mov     x3, x0                    // buf
    mov     x4, x1                    // length
    mov     x5, x2                    // ptr array
    mov     x0, #0                    // count
    mov     x9, #0                    // i
.sl_line:
    cmp     x9, x4
    b.hs    .sl_done
    cmp     x0, #MAXL
    b.hs    .sl_scan
    add     x10, x3, x9
    str     x10, [x5, x0, lsl #3]
    add     x0, x0, #1
.sl_scan:
    cmp     x9, x4
    b.hs    .sl_done
    ldrb    w10, [x3, x9]
    cmp     w10, #0x0a
    b.ne    .sl_noNL
    strb    wzr, [x3, x9]
    add     x9, x9, #1
    b       .sl_line
.sl_noNL:
    add     x9, x9, #1
    b       .sl_scan
.sl_done:
    ret

// line_cmp(x0, x1) -> x0: byte comparison of NUL-terminated strings. Leaf.
line_cmp:
    mov     x2, #0
.lc_l:
    ldrb    w3, [x0, x2]
    ldrb    w4, [x1, x2]
    cmp     w3, w4
    b.ne    .lc_diff
    cbz     w3, .lc_eq
    add     x2, x2, #1
    b       .lc_l
.lc_diff:
    sub     w0, w3, w4
    sxtw    x0, w0
    ret
.lc_eq:
    mov     x0, #0
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

err_usage: .asciz "uolt-comm: usage: comm [-1] [-2] [-3] file1 file2\n"
err_pre:   .asciz "uolt-comm: "
err_suf:   .asciz ": cannot open\n"
