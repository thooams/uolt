// src/cut/arm64/cut.S - the POSIX `cut` utility, aarch64.
//
// cut -c LIST [file...]                    select 1-based character positions
// cut -f LIST [-d DELIM] [-s] [file...]    select delimiter-separated fields
//
// LIST is a comma-separated list of positions and ranges: N, N-M, N- (to end of
// line), -M (from the start). For -f the default delimiter is a tab; a line with
// no delimiter is passed through unchanged, unless -s drops it. Selected positions
// live in a bitmap (plus an open-ended threshold) on the stack (no heap, Principle
// IV); input is read in 64 KB blocks and split into lines. Mirrors the x86_64 body.
//
// Global reg: x19 = line buffer; the bitmap is at [x19 + BUFSZ]. Stack locals off
// x29. main uses x20 = argc-1 walk count, x21 = &argv walk, x22 = token/fd.

#include "uolt.inc"

.set STDIN,    0
.set STDOUT,   1
.set STDERR,   2
.set O_RDONLY, 0
.set BUFSZ,    65536
.set BITMAP,   1024                     // 8192 positions

.set LOC_MODE,  48
.set LOC_DELIM, 56
.set LOC_TOEND, 64
.set LOC_STAT,  72
.set LOC_CH,    80
.set LOC_S,     88

.text
.globl uolt_main
uolt_main:
    sub     sp, sp, #128
    mov     x29, sp
    stp     x19, x20, [sp, #0]
    stp     x21, x22, [sp, #16]
    str     x30, [sp, #32]
    sub     sp, sp, #65536             // BUFSZ
    sub     sp, sp, #1152             // BITMAP + 128 slack
    mov     x19, sp
    str     xzr, [x29, #LOC_MODE]
    mov     w9, #0x09
    strb    w9, [x29, #LOC_DELIM]
    str     xzr, [x29, #LOC_TOEND]
    str     xzr, [x29, #LOC_STAT]
    str     xzr, [x29, #LOC_S]
    // clear the bitmap
    add     x9, x19, #BUFSZ
    mov     x10, #0
.clrbm:
    str     xzr, [x9, x10, lsl #3]
    add     x10, x10, #1
    cmp     x10, #128                 // BITMAP/8
    b.ne    .clrbm

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
    cmp     w9, #'c'
    b.eq    .opt_list
    cmp     w9, #'f'
    b.eq    .opt_list
    cmp     w9, #'d'
    b.eq    .opt_delim
    cmp     w9, #'s'
    b.eq    .opt_s
    cmp     w9, #'-'
    b.eq    .opt_ddash
    b       .after
.opt_s:
    ldrb    w10, [x22, #2]             // only the standalone "-s"
    cbnz    w10, .after
    mov     x10, #1
    str     x10, [x29, #LOC_S]
    add     x21, x21, #8
    sub     x20, x20, #1
    b       .opt
.opt_list:
    strb    w9, [x29, #LOC_MODE]       // 'c' or 'f'
    add     x0, x22, #2
    ldrb    w10, [x0]
    cbnz    w10, .have_list
    add     x21, x21, #8
    sub     x20, x20, #1
    cbz     x20, .usage
    ldr     x0, [x21]
.have_list:
    bl      parse_list
    add     x21, x21, #8
    sub     x20, x20, #1
    b       .opt
.opt_delim:
    add     x0, x22, #2
    ldrb    w10, [x0]
    cbnz    w10, .have_delim
    add     x21, x21, #8
    sub     x20, x20, #1
    cbz     x20, .usage
    ldr     x0, [x21]
.have_delim:
    ldrb    w9, [x0]
    strb    w9, [x29, #LOC_DELIM]
    add     x21, x21, #8
    sub     x20, x20, #1
    b       .opt
.opt_ddash:
    ldrb    w9, [x22, #2]
    cbnz    w9, .after
    add     x21, x21, #8
    sub     x20, x20, #1
.after:
    ldr     x9, [x29, #LOC_MODE]
    cbz     x9, .usage
    cbz     x20, .use_stdin
.floop:
    cbz     x20, .fin
    ldr     x0, [x21]
    mov     x1, #O_RDONLY
    mov     x2, #0
    bl      uolt_open
    cmp     x0, #0
    b.mi    .fopenerr
    mov     x22, x0                    // fd
    mov     x0, x22
    bl      run_fd
    mov     x0, x22
    bl      uolt_close
    b       .fnext
.fopenerr:
    mov     x9, #1
    str     x9, [x29, #LOC_STAT]
    adr     x0, err_pre
    bl      err_puts
    ldr     x0, [x21]
    bl      err_puts
    adr     x0, err_suf
    bl      err_puts
.fnext:
    add     x21, x21, #8
    sub     x20, x20, #1
    b       .floop
.use_stdin:
    mov     x0, #STDIN
    bl      run_fd
.fin:
    ldr     x0, [x29, #LOC_STAT]
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
    add     sp, sp, #128
    ret

// run_fd(x0 = fd): read the descriptor and cut each line. Saves x20/x21/x22.
run_fd:
    sub     sp, sp, #48
    stp     x20, x21, [sp, #0]
    stp     x22, x30, [sp, #16]
    mov     x20, x0                    // fd
    mov     x21, #0                    // fill
.rf_rd:
    mov     x2, #BUFSZ
    sub     x2, x2, x21
    cbz     x2, .rf_long
    mov     x0, x20
    add     x1, x19, x21
    bl      uolt_read
    cmp     x0, #0
    b.le    .rf_eof
    add     x21, x21, x0               // fill += n
    mov     x22, #0                    // line start
.rf_scan:
    mov     x9, x22                    // find cursor
.rf_find:
    cmp     x9, x21
    b.hs    .rf_compact
    ldrb    w10, [x19, x9]
    cmp     w10, #0x0a
    b.eq    .rf_line
    add     x9, x9, #1
    b       .rf_find
.rf_line:
    add     x0, x19, x22               // line ptr
    sub     x1, x9, x22                // length
    add     x22, x9, #1                // next line start
    bl      cut_line
    b       .rf_scan
.rf_compact:
    sub     x11, x21, x22              // bytes remaining
    mov     x9, #0
.rf_cp:
    cmp     x9, x11
    b.hs    .rf_cpd
    add     x12, x19, x22
    ldrb    w13, [x12, x9]
    strb    w13, [x19, x9]
    add     x9, x9, #1
    b       .rf_cp
.rf_cpd:
    mov     x21, x11
    b       .rf_rd
.rf_long:
    mov     x0, x19
    mov     x1, x21
    bl      cut_line
    mov     x21, #0
    b       .rf_rd
.rf_eof:
    cbz     x21, .rf_ret
    mov     x0, x19
    mov     x1, x21
    bl      cut_line
.rf_ret:
    ldp     x20, x21, [sp, #0]
    ldp     x22, x30, [sp, #16]
    add     sp, sp, #48
    ret

// cut_line(x0 = line ptr, x1 = length): emit the selected part + a newline.
// x20=ptr, x21=len, x22=run start/field index, x23=position/field start,
// x24=scan pos, x25=any-output. Saves x20-x25.
cut_line:
    sub     sp, sp, #64
    stp     x20, x21, [sp, #0]
    stp     x22, x23, [sp, #16]
    stp     x24, x25, [sp, #32]
    str     x30, [sp, #48]
    mov     x20, x0
    mov     x21, x1
    ldrb    w9, [x29, #LOC_MODE]
    cmp     w9, #'f'
    b.eq    .cl_fields
    // -c: emit selected character positions as contiguous runs
    mov     x22, #0                    // run start (0 = none)
    mov     x23, #1                    // position i
.cl_c:
    cmp     x23, x21
    b.gt    .cl_c_end
    mov     x0, x23
    bl      selected
    cbz     x0, .cl_c_off
    cbnz    x22, .cl_c_next
    mov     x22, x23                   // open a run
    b       .cl_c_next
.cl_c_off:
    bl      .cl_flush_run
.cl_c_next:
    add     x23, x23, #1
    b       .cl_c
.cl_c_end:
    bl      .cl_flush_run
    b       .cl_nl
.cl_flush_run:
    cbz     x22, .fr_done
    add     x1, x20, x22
    sub     x1, x1, #1                 // run start byte
    sub     x2, x23, x22               // run length
    mov     x0, #STDOUT
    stp     x29, x30, [sp, #-16]!
    bl      uolt_write
    ldp     x29, x30, [sp], #16
    mov     x22, #0
.fr_done:
    ret

.cl_fields:
    // If the line has no delimiter, pass it through unchanged.
    ldrb    w11, [x29, #LOC_DELIM]
    mov     x10, #0
.cl_hasd:
    cmp     x10, x21
    b.hs    .cl_whole
    ldrb    w9, [x20, x10]
    cmp     w9, w11
    b.eq    .cl_split
    add     x10, x10, #1
    b       .cl_hasd
.cl_whole:
    ldr     x9, [x29, #LOC_S]          // -s: drop lines without a delimiter
    cbnz    x9, .cl_ret
    mov     x1, x20
    mov     x2, x21
    mov     x0, #STDOUT
    bl      uolt_write
    b       .cl_nl
.cl_split:
    mov     x22, #1                    // field index (1-based)
    mov     x23, #0                    // field start
    mov     x25, #0                    // any output yet
    mov     x24, #0                    // scan position
.cl_f:
    cmp     x24, x21
    b.hs    .cl_flast
    ldrb    w11, [x29, #LOC_DELIM]
    ldrb    w9, [x20, x24]
    cmp     w9, w11
    b.ne    .cl_f_next
    mov     x0, x22
    bl      selected
    cbz     x0, .cl_f_noemit
    bl      .cl_emit_field             // field [x23, x24)
.cl_f_noemit:
    add     x22, x22, #1
    add     x23, x24, #1               // next field start
.cl_f_next:
    add     x24, x24, #1
    b       .cl_f
.cl_flast:
    mov     x0, x22
    bl      selected
    cbz     x0, .cl_nl
    bl      .cl_emit_field
    b       .cl_nl
.cl_emit_field:
    // emit a delimiter before every field except the first output one
    stp     x29, x30, [sp, #-16]!
    cbz     x25, .cef_nodelim
    ldrb    w9, [x29, #LOC_DELIM]
    strb    w9, [x29, #LOC_CH]
    mov     x0, #STDOUT
    add     x1, x29, #LOC_CH
    mov     x2, #1
    bl      uolt_write
.cef_nodelim:
    mov     x25, #1
    add     x1, x20, x23               // field start
    sub     x2, x24, x23               // field length
    mov     x0, #STDOUT
    bl      uolt_write
    ldp     x29, x30, [sp], #16
    ret

.cl_nl:
    mov     w9, #0x0a
    strb    w9, [x29, #LOC_CH]
    mov     x0, #STDOUT
    add     x1, x29, #LOC_CH
    mov     x2, #1
    bl      uolt_write
.cl_ret:
    ldp     x20, x21, [sp, #0]
    ldp     x22, x23, [sp, #16]
    ldp     x24, x25, [sp, #32]
    ldr     x30, [sp, #48]
    add     sp, sp, #64
    ret

// selected(x0 = 1-based position) -> x0 = 1 if selected, else 0. Leaf.
selected:
    ldr     x1, [x29, #LOC_TOEND]
    cbz     x1, .sel_lo
    cmp     x0, x1
    b.hs    .sel_yes
.sel_lo:
    sub     x0, x0, #1
    mov     x2, #8192                  // BITMAP*8
    cmp     x0, x2
    b.hs    .sel_no
    and     x1, x0, #7
    lsr     x0, x0, #3
    add     x3, x19, #BUFSZ
    ldrb    w2, [x3, x0]
    lsr     w2, w2, w1
    and     x0, x2, #1
    ret
.sel_yes:
    mov     x0, #1
    ret
.sel_no:
    mov     x0, #0
    ret

// parse_list(x0 = LIST string): set the selected bits / open-end threshold.
// State in x9-x13; set_bit preserves those. Saves lr.
parse_list:
    stp     x29, x30, [sp, #-16]!
    mov     x9, x0                     // list cursor
.pl_next:
    ldrb    w0, [x9]
    cbz     w0, .pl_end
    mov     x10, #0                    // lo
    mov     x11, #0                    // lo present
.pl_lo:
    ldrb    w0, [x9]
    sub     w0, w0, #'0'
    cmp     w0, #9
    b.hi    .pl_lo_done
    add     x10, x10, x10, lsl #2
    add     x10, x10, x10              // *10
    add     x10, x10, w0, uxtw
    mov     x11, #1
    add     x9, x9, #1
    b       .pl_lo
.pl_lo_done:
    ldrb    w0, [x9]
    cmp     w0, #'-'
    b.eq    .pl_range
    cbz     x11, .pl_skip
    mov     x0, x10
    bl      set_bit
    b       .pl_skip
.pl_range:
    add     x9, x9, #1
    mov     x12, #0                    // hi
    mov     x13, #0                    // hi present
.pl_hi:
    ldrb    w0, [x9]
    sub     w0, w0, #'0'
    cmp     w0, #9
    b.hi    .pl_hi_done
    add     x12, x12, x12, lsl #2
    add     x12, x12, x12
    add     x12, x12, w0, uxtw
    mov     x13, #1
    add     x9, x9, #1
    b       .pl_hi
.pl_hi_done:
    cbnz    x11, .pl_lo_ok
    mov     x10, #1                    // "-M" -> lo defaults to 1
.pl_lo_ok:
    cbz     x13, .pl_open
.pl_sr:
    cmp     x10, x12
    b.gt    .pl_skip
    mov     x0, x10
    bl      set_bit
    add     x10, x10, #1
    b       .pl_sr
.pl_open:
    ldr     x0, [x29, #LOC_TOEND]
    cbz     x0, .pl_setend
    cmp     x10, x0
    b.hs    .pl_skip
.pl_setend:
    str     x10, [x29, #LOC_TOEND]
.pl_skip:
    ldrb    w0, [x9]
    cbz     w0, .pl_end
    cmp     w0, #','
    b.eq    .pl_comma
    add     x9, x9, #1
    b       .pl_skip
.pl_comma:
    add     x9, x9, #1
    b       .pl_next
.pl_end:
    ldp     x29, x30, [sp], #16
    ret

// set_bit(x0 = 1-based position): set the bit. Uses only x0/x1/x2/x3, so
// parse_list's x9-x13 survive. Leaf.
set_bit:
    cbz     x0, .sb_ret
    sub     x0, x0, #1
    mov     x2, #8192                  // BITMAP*8
    cmp     x0, x2
    b.hs    .sb_ret
    and     x1, x0, #7
    lsr     x0, x0, #3
    mov     w2, #1
    lsl     w2, w2, w1
    add     x3, x19, #BUFSZ
    ldrb    w1, [x3, x0]
    orr     w1, w1, w2
    strb    w1, [x3, x0]
.sb_ret:
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

err_usage: .asciz "uolt-cut: usage: cut -c LIST | -f LIST [-d DELIM] [-s] [file...]\n"
err_pre:   .asciz "uolt-cut: "
err_suf:   .asciz ": cannot open\n"
