// src/sort/arm64/sort.S - the `sort` utility (lexicographic), aarch64.
//
// sort [-rnufb] [file...]: read all input lines, sort them in C-locale byte order,
// and write them out. -r reverses, -n compares leading integers, -u drops adjacent
// equal-key lines, -f folds case, -b ignores leading blanks. No file -> stdin;
// several files are concatenated. Stable (ties keep input order). Mirrors the
// x86_64 body.
//
// Text and line-pointer arrays are mmap'd regions that GROW on demand (double,
// copy, unmap), so cost tracks the actual input and a real OOM is reported, never
// silent truncation (Principle IV allows an explicit, failure-checked mmap). The
// sort is a stable bottom-up merge sort over the pointer array with a third region
// as ping-pong scratch. Line pointers are computed only after all input is read.
//
// Callee-saved: x19 = text region; x20 = current line-pointer array; x21 = line
//   count; x22 = text fill then merge run width; x23 = operand count then emit
//   counter. Locals off x29; mem_err resets sp via x29.

#include "uolt.inc"

.set STDIN,    0
.set STDOUT,   1
.set STDERR,   2
.set O_RDONLY, 0

.set TEXT_START, 0x800000
.set PTR_START,  0x100000
.set OBSIZE,     0x10000

.set LOC_FLAGS,   64            // bit0 -r, bit1 -n, bit2 -u, bit3 -f, bit4 -b
.set LOC_ARGV,    72
.set LOC_AUX,     80
.set LOC_SRC,     88
.set LOC_DST,     96
.set LOC_I,       104
.set LOC_MID,     112
.set LOC_END,     120
.set LOC_LI,      128
.set LOC_RI,      136
.set LOC_DI,      144
.set LOC_TCAP,    152
.set LOC_PCAP,    160
.set LOC_NEWCAP,  168
.set LOC_NEWBASE, 176
.set LOC_OBLEN,   184
.set OBUFOFF,     192            // output buffer [192, 192+OBSIZE)
.set FRAME,       65728

.text
.globl uolt_main
uolt_main:
    sub     sp, sp, #65536
    sub     sp, sp, #192
    mov     x29, sp
    str     x30, [x29, #0]
    stp     x19, x20, [x29, #16]
    stp     x21, x22, [x29, #32]
    str     x23, [x29, #48]

    add     x9, x1, #8                 // &argv[1]
    str     x9, [x29, #LOC_ARGV]
    sub     x23, x0, #1                // operand count
    str     xzr, [x29, #LOC_FLAGS]

    mov     x0, #TEXT_START
    bl      uolt_mmap_anon
    cmp     x0, #0
    b.mi    mem_err
    mov     x19, x0
    mov     x9, #TEXT_START
    str     x9, [x29, #LOC_TCAP]
    mov     x0, #PTR_START
    bl      uolt_mmap_anon
    cmp     x0, #0
    b.mi    mem_err
    mov     x20, x0
    mov     x9, #PTR_START
    str     x9, [x29, #LOC_PCAP]

    mov     x21, #0                    // line count
    mov     x22, #0                    // text fill
    str     xzr, [x29, #LOC_OBLEN]
.opt:
    cbz     x23, .files
    ldr     x9, [x29, #LOC_ARGV]
    ldr     x10, [x9]
    ldrb    w11, [x10]
    cmp     w11, #'-'
    b.ne    .files
    ldrb    w11, [x10, #1]
    cbz     w11, .files                // "-" -> stdin operand
    cmp     w11, #'-'
    b.ne    .optletters
    ldrb    w11, [x10, #2]
    cbnz    w11, .optletters
    ldr     x9, [x29, #LOC_ARGV]
    add     x9, x9, #8                  // "--"
    str     x9, [x29, #LOC_ARGV]
    sub     x23, x23, #1
    b       .files
.optletters:
    add     x12, x10, #1
.optf:
    ldrb    w11, [x12]
    cbz     w11, .optdone
    cmp     w11, #'r'
    b.ne    .of5
    ldr     x9, [x29, #LOC_FLAGS]
    orr     x9, x9, #1
    str     x9, [x29, #LOC_FLAGS]
    b       .optfn
.of5:
    cmp     w11, #'n'
    b.ne    .of6
    ldr     x9, [x29, #LOC_FLAGS]
    orr     x9, x9, #2
    str     x9, [x29, #LOC_FLAGS]
    b       .optfn
.of6:
    cmp     w11, #'u'
    b.ne    .of7
    ldr     x9, [x29, #LOC_FLAGS]
    orr     x9, x9, #4
    str     x9, [x29, #LOC_FLAGS]
    b       .optfn
.of7:
    cmp     w11, #'f'
    b.ne    .of8
    ldr     x9, [x29, #LOC_FLAGS]
    orr     x9, x9, #8
    str     x9, [x29, #LOC_FLAGS]
    b       .optfn
.of8:
    cmp     w11, #'b'
    b.ne    .files
    ldr     x9, [x29, #LOC_FLAGS]
    orr     x9, x9, #16
    str     x9, [x29, #LOC_FLAGS]
.optfn:
    add     x12, x12, #1
    b       .optf
.optdone:
    ldr     x9, [x29, #LOC_ARGV]
    add     x9, x9, #8
    str     x9, [x29, #LOC_ARGV]
    sub     x23, x23, #1
    b       .opt

.files:
    cbnz    x23, .floop
    mov     x0, #STDIN
    bl      read_into
    b       .split
.floop:
    cbz     x23, .split
    ldr     x9, [x29, #LOC_ARGV]
    ldr     x10, [x9]
    ldrb    w11, [x10]
    cmp     w11, #'-'
    b.ne    .f_open
    ldrb    w11, [x10, #1]
    cbnz    w11, .f_open
    mov     x0, #STDIN
    bl      read_into
    b       .fnext
.f_open:
    ldr     x9, [x29, #LOC_ARGV]
    ldr     x0, [x9]
    mov     x1, #O_RDONLY
    mov     x2, #0
    bl      uolt_open
    cmp     x0, #0
    b.mi    .fnext
    mov     x24, x0                    // fd
    mov     x0, x24
    bl      read_into
    mov     x0, x24
    bl      uolt_close
.fnext:
    ldr     x9, [x29, #LOC_ARGV]
    add     x9, x9, #8
    str     x9, [x29, #LOC_ARGV]
    sub     x23, x23, #1
    b       .floop

.split:
    mov     x25, #0                    // scan index i (survives grow_ptr)
.sp_line:
    cmp     x25, x22
    b.hs    .sp_done
    lsl     x9, x21, #3                // ensure room for one more pointer
    ldr     x10, [x29, #LOC_PCAP]
    cmp     x9, x10
    b.lo    .sp_room
    bl      grow_ptr
.sp_room:
    add     x9, x19, x25
    str     x9, [x20, x21, lsl #3]
    add     x21, x21, #1
.sp_find:
    cmp     x25, x22
    b.hs    .sp_done
    ldrb    w9, [x19, x25]
    cmp     w9, #0x0a
    b.eq    .sp_nl
    add     x25, x25, #1
    b       .sp_find
.sp_nl:
    strb    wzr, [x19, x25]
    add     x25, x25, #1
    b       .sp_line
.sp_done:
    ldr     x0, [x29, #LOC_PCAP]        // scratch array, same capacity
    bl      uolt_mmap_anon
    cmp     x0, #0
    b.mi    mem_err
    str     x0, [x29, #LOC_AUX]

    bl      merge_sort                 // sort x20[0, x21); result left in x20

.emit:
    mov     x23, #0
.em_loop:
    cmp     x23, x21
    b.hs    .fin
    ldr     x9, [x29, #LOC_FLAGS]
    tbz     x9, #2, .em_print          // -u: drop lines equal to the previous
    cbz     x23, .em_print
    sub     x10, x23, #1
    ldr     x0, [x20, x10, lsl #3]
    ldr     x1, [x20, x23, lsl #3]
    bl      key_cmp
    cbz     x0, .em_skip
    ldr     x0, [x20, x23, lsl #3]
    b       .em_do
.em_print:
    ldr     x0, [x20, x23, lsl #3]
.em_do:
    bl      put_line
.em_skip:
    add     x23, x23, #1
    b       .em_loop

.fin:
    bl      ob_flush
    mov     x0, #0
    b       .epi
mem_err:
    adr     x0, err_nomem
    mov     x3, x0
    bl      uolt_strlen
    mov     x2, x0
    mov     x1, x3
    mov     x0, #STDERR
    bl      uolt_write
    mov     x0, #2
.epi:
    mov     sp, x29
    ldr     x30, [x29, #0]
    ldp     x19, x20, [x29, #16]
    ldp     x21, x22, [x29, #32]
    ldr     x23, [x29, #48]
    add     sp, sp, #65536
    add     sp, sp, #192
    ret

// grow_text(): double the text region, copy the x22 bytes, unmap, update x19.
grow_text:
    stp     x29, x30, [sp, #-16]!
    ldr     x0, [x29, #LOC_TCAP]
    add     x0, x0, x0
    str     x0, [x29, #LOC_NEWCAP]
    bl      uolt_mmap_anon
    cmp     x0, #0
    b.mi    mem_err
    str     x0, [x29, #LOC_NEWBASE]
    mov     x9, #0
.gt_cp:
    cmp     x9, x22
    b.hs    .gt_cpd
    ldrb    w10, [x19, x9]
    strb    w10, [x0, x9]
    add     x9, x9, #1
    b       .gt_cp
.gt_cpd:
    mov     x0, x19
    ldr     x1, [x29, #LOC_TCAP]
    bl      uolt_munmap
    ldr     x19, [x29, #LOC_NEWBASE]
    ldr     x9, [x29, #LOC_NEWCAP]
    str     x9, [x29, #LOC_TCAP]
    ldp     x29, x30, [sp], #16
    ret

// grow_ptr(): double the pointer array, copy the x21 pointers, unmap, update x20.
grow_ptr:
    stp     x29, x30, [sp, #-16]!
    ldr     x0, [x29, #LOC_PCAP]
    add     x0, x0, x0
    str     x0, [x29, #LOC_NEWCAP]
    bl      uolt_mmap_anon
    cmp     x0, #0
    b.mi    mem_err
    str     x0, [x29, #LOC_NEWBASE]
    lsl     x11, x21, #3
    mov     x9, #0
.gp_cp:
    cmp     x9, x11
    b.hs    .gp_cpd
    ldrb    w10, [x20, x9]
    strb    w10, [x0, x9]
    add     x9, x9, #1
    b       .gp_cp
.gp_cpd:
    mov     x0, x20
    ldr     x1, [x29, #LOC_PCAP]
    bl      uolt_munmap
    ldr     x20, [x29, #LOC_NEWBASE]
    ldr     x9, [x29, #LOC_NEWCAP]
    str     x9, [x29, #LOC_PCAP]
    ldp     x29, x30, [sp], #16
    ret

// read_into(x0 = fd): append the descriptor's bytes to [x19 + x22], growing the
// text region when it fills. Preserves x23 and LOC_ARGV. x24 = fd.
read_into:
    stp     x24, x30, [sp, #-16]!
    mov     x24, x0
.ri_read:
    ldr     x9, [x29, #LOC_TCAP]
    cmp     x22, x9
    b.lo    .ri_have
    bl      grow_text
.ri_have:
    ldr     x2, [x29, #LOC_TCAP]
    sub     x2, x2, x22
    mov     x0, x24
    add     x1, x19, x22
    bl      uolt_read
    cmp     x0, #0
    b.le    .ri_done
    add     x22, x22, x0
    b       .ri_read
.ri_done:
    ldp     x24, x30, [sp], #16
    ret

// merge_sort(): stable bottom-up merge sort of x20[0, x21) using LOC_AUX as
// ping-pong scratch. On return x20 points at whichever array holds the result.
merge_sort:
    stp     x29, x30, [sp, #-16]!      // calls line_cmp (bl), so preserve lr
    cmp     x21, #2
    b.lo    .ms_ret
    str     x20, [x29, #LOC_SRC]
    ldr     x9, [x29, #LOC_AUX]
    str     x9, [x29, #LOC_DST]
    mov     x22, #1                    // run width
.ms_pass:
    cmp     x22, x21
    b.hs    .ms_finish
    str     xzr, [x29, #LOC_I]
.ms_run:
    ldr     x9, [x29, #LOC_I]
    cmp     x9, x21
    b.hs    .ms_swap
    add     x10, x9, x22               // mid = min(i + width, n)
    cmp     x10, x21
    b.ls    .ms_mid_ok
    mov     x10, x21
.ms_mid_ok:
    str     x10, [x29, #LOC_MID]
    add     x10, x10, x22              // end = min(mid + width, n)
    cmp     x10, x21
    b.ls    .ms_end_ok
    mov     x10, x21
.ms_end_ok:
    str     x10, [x29, #LOC_END]
    ldr     x9, [x29, #LOC_I]
    str     x9, [x29, #LOC_LI]
    str     x9, [x29, #LOC_DI]
    ldr     x9, [x29, #LOC_MID]
    str     x9, [x29, #LOC_RI]
.mg_loop:
    ldr     x9, [x29, #LOC_LI]
    ldr     x10, [x29, #LOC_MID]
    cmp     x9, x10
    b.hs    .mg_rest_right
    ldr     x9, [x29, #LOC_RI]
    ldr     x10, [x29, #LOC_END]
    cmp     x9, x10
    b.hs    .mg_rest_left
    ldr     x11, [x29, #LOC_SRC]
    ldr     x9, [x29, #LOC_LI]
    ldr     x0, [x11, x9, lsl #3]
    ldr     x9, [x29, #LOC_RI]
    ldr     x1, [x11, x9, lsl #3]
    bl      line_cmp
    ldr     x9, [x29, #LOC_FLAGS]
    tbz     x9, #0, .mg_norev          // -r reverses
    neg     x0, x0
.mg_norev:
    cmp     x0, #0
    b.le    .mg_take_left              // a <= b: take left (stable on ties)
    ldr     x11, [x29, #LOC_SRC]
    ldr     x9, [x29, #LOC_RI]
    ldr     x12, [x11, x9, lsl #3]
    ldr     x11, [x29, #LOC_DST]
    ldr     x9, [x29, #LOC_DI]
    str     x12, [x11, x9, lsl #3]
    ldr     x9, [x29, #LOC_RI]
    add     x9, x9, #1
    str     x9, [x29, #LOC_RI]
    ldr     x9, [x29, #LOC_DI]
    add     x9, x9, #1
    str     x9, [x29, #LOC_DI]
    b       .mg_loop
.mg_take_left:
    ldr     x11, [x29, #LOC_SRC]
    ldr     x9, [x29, #LOC_LI]
    ldr     x12, [x11, x9, lsl #3]
    ldr     x11, [x29, #LOC_DST]
    ldr     x9, [x29, #LOC_DI]
    str     x12, [x11, x9, lsl #3]
    ldr     x9, [x29, #LOC_LI]
    add     x9, x9, #1
    str     x9, [x29, #LOC_LI]
    ldr     x9, [x29, #LOC_DI]
    add     x9, x9, #1
    str     x9, [x29, #LOC_DI]
    b       .mg_loop
.mg_rest_left:
    ldr     x9, [x29, #LOC_LI]
    ldr     x10, [x29, #LOC_MID]
    cmp     x9, x10
    b.hs    .mg_run_done
    ldr     x11, [x29, #LOC_SRC]
    ldr     x12, [x11, x9, lsl #3]
    ldr     x11, [x29, #LOC_DST]
    ldr     x10, [x29, #LOC_DI]
    str     x12, [x11, x10, lsl #3]
    ldr     x9, [x29, #LOC_LI]
    add     x9, x9, #1
    str     x9, [x29, #LOC_LI]
    ldr     x9, [x29, #LOC_DI]
    add     x9, x9, #1
    str     x9, [x29, #LOC_DI]
    b       .mg_rest_left
.mg_rest_right:
    ldr     x9, [x29, #LOC_RI]
    ldr     x10, [x29, #LOC_END]
    cmp     x9, x10
    b.hs    .mg_run_done
    ldr     x11, [x29, #LOC_SRC]
    ldr     x12, [x11, x9, lsl #3]
    ldr     x11, [x29, #LOC_DST]
    ldr     x10, [x29, #LOC_DI]
    str     x12, [x11, x10, lsl #3]
    ldr     x9, [x29, #LOC_RI]
    add     x9, x9, #1
    str     x9, [x29, #LOC_RI]
    ldr     x9, [x29, #LOC_DI]
    add     x9, x9, #1
    str     x9, [x29, #LOC_DI]
    b       .mg_rest_right
.mg_run_done:
    add     x10, x22, x22              // i += 2 * width
    ldr     x9, [x29, #LOC_I]
    add     x9, x9, x10
    str     x9, [x29, #LOC_I]
    b       .ms_run
.ms_swap:
    ldr     x9, [x29, #LOC_SRC]
    ldr     x10, [x29, #LOC_DST]
    str     x10, [x29, #LOC_SRC]
    str     x9, [x29, #LOC_DST]
    add     x22, x22, x22              // width *= 2
    b       .ms_pass
.ms_finish:
    ldr     x9, [x29, #LOC_SRC]
    mov     x20, x9
.ms_ret:
    ldp     x29, x30, [sp], #16
    ret

// line_cmp(x0 = a, x1 = b) -> x0: key comparison with a raw-byte last-resort
// tiebreak. Frame: [0]lr [8]a [16]b.
line_cmp:
    sub     sp, sp, #32
    str     x30, [sp, #0]
    str     x0, [sp, #8]
    str     x1, [sp, #16]
    bl      key_cmp
    cbnz    x0, .lc_done
    ldr     x0, [sp, #8]
    ldr     x1, [sp, #16]
    mov     x2, #0
.lc_raw:
    ldrb    w3, [x0, x2]
    ldrb    w4, [x1, x2]
    cmp     w3, w4
    b.ne    .lc_rdiff
    cbz     w3, .lc_req
    add     x2, x2, #1
    b       .lc_raw
.lc_rdiff:
    sub     w0, w3, w4
    sxtw    x0, w0
    ldr     x30, [sp, #0]
    add     sp, sp, #32
    ret
.lc_req:
    mov     x0, #0
    ldr     x30, [sp, #0]
    add     sp, sp, #32
    ret
.lc_done:
    ldr     x30, [sp, #0]
    add     sp, sp, #32
    ret

// key_cmp(x0 = a, x1 = b) -> x0: <0/0/>0 on the sort keys.
key_cmp:
    ldr     x9, [x29, #LOC_FLAGS]
    tbnz    x9, #1, num_cmp            // -n
    tbz     x9, #4, .kc_scan           // -b
.kc_ba:
    ldrb    w10, [x0]
    cmp     w10, #' '
    b.eq    .kc_ba_adv
    cmp     w10, #0x09
    b.ne    .kc_bb
.kc_ba_adv:
    add     x0, x0, #1
    b       .kc_ba
.kc_bb:
    ldrb    w10, [x1]
    cmp     w10, #' '
    b.eq    .kc_bb_adv
    cmp     w10, #0x09
    b.ne    .kc_scan
.kc_bb_adv:
    add     x1, x1, #1
    b       .kc_bb
.kc_scan:
    mov     x2, #0
    ldr     x11, [x29, #LOC_FLAGS]
.kc_l:
    ldrb    w3, [x0, x2]
    ldrb    w4, [x1, x2]
    tbz     x11, #3, .kc_cmp           // -f
    cmp     w3, #'A'
    b.lo    .kc_f2
    cmp     w3, #'Z'
    b.hi    .kc_f2
    add     w3, w3, #0x20
.kc_f2:
    cmp     w4, #'A'
    b.lo    .kc_cmp
    cmp     w4, #'Z'
    b.hi    .kc_cmp
    add     w4, w4, #0x20
.kc_cmp:
    cmp     w3, w4
    b.ne    .kc_diff
    cbz     w3, .kc_eq
    add     x2, x2, #1
    b       .kc_l
.kc_diff:
    sub     w0, w3, w4
    sxtw    x0, w0
    ret
.kc_eq:
    mov     x0, #0
    ret

// num_cmp(x0 = a, x1 = b) -> x0. Frame: [0]lr [8]b [16]v_a.
num_cmp:
    sub     sp, sp, #32
    str     x30, [sp, #0]
    str     x1, [sp, #8]
    bl      parse_num
    str     x0, [sp, #16]
    ldr     x0, [sp, #8]
    bl      parse_num
    ldr     x9, [sp, #16]
    cmp     x9, x0
    b.lt    .nc_lt
    b.gt    .nc_gt
    mov     x0, #0
    b       .nc_ret
.nc_lt:
    mov     x0, #-1
    b       .nc_ret
.nc_gt:
    mov     x0, #1
.nc_ret:
    ldr     x30, [sp, #0]
    add     sp, sp, #32
    ret

// parse_num(x0 = ASCIZ) -> x0: leading integer. Leaf.
parse_num:
    mov     x1, x0                     // cursor
    mov     x0, #0                     // value
    mov     x2, #0                     // negative flag
.pn_sp:
    ldrb    w3, [x1]
    cmp     w3, #' '
    b.eq    .pn_adv
    cmp     w3, #0x09
    b.ne    .pn_sign
.pn_adv:
    add     x1, x1, #1
    b       .pn_sp
.pn_sign:
    cmp     w3, #'-'
    b.ne    .pn_plus
    mov     x2, #1
    add     x1, x1, #1
    b       .pn_dig
.pn_plus:
    cmp     w3, #'+'
    b.ne    .pn_dig
    add     x1, x1, #1
.pn_dig:
    ldrb    w3, [x1]
    sub     w3, w3, #'0'
    cmp     w3, #9
    b.hi    .pn_done
    mov     x4, #10
    mul     x0, x0, x4
    add     x0, x0, w3, uxtw
    add     x1, x1, #1
    b       .pn_dig
.pn_done:
    cbz     x2, .pn_ret
    neg     x0, x0
.pn_ret:
    ret

// put_line(x0 = ASCIZ line): append the line and a newline to OBUF.
put_line:
    sub     sp, sp, #32
    str     x30, [sp, #0]
    str     x0, [sp, #8]
    bl      uolt_strlen
    ldr     x1, [sp, #8]
    mov     x2, x0
    bl      ob_put
    adr     x1, nl_char
    mov     x2, #1
    bl      ob_put
    ldr     x30, [sp, #0]
    add     sp, sp, #32
    ret

// ob_put(x1 = src, x2 = len): append len bytes to OBUF, flushing when full.
// x24 = src, x25 = len (saved so they survive ob_flush).
ob_put:
    stp     x24, x25, [sp, #-32]!
    str     x30, [sp, #16]
    mov     x24, x1
    mov     x25, x2
.op_l:
    cbz     x25, .op_ret
    ldr     x9, [x29, #LOC_OBLEN]
    cmp     x9, #OBSIZE
    b.lo    .op_room
    bl      ob_flush
    mov     x9, #0
.op_room:
    mov     x10, #OBSIZE
    sub     x10, x10, x9               // space left
    cmp     x10, x25
    b.ls    .op_cap
    mov     x10, x25                   // copy = min(space, len)
.op_cap:
    add     x11, x29, #OBUFOFF
    add     x11, x11, x9
    mov     x12, #0
.op_cp:
    cmp     x12, x10
    b.hs    .op_cpd
    ldrb    w13, [x24, x12]
    strb    w13, [x11, x12]
    add     x12, x12, #1
    b       .op_cp
.op_cpd:
    ldr     x9, [x29, #LOC_OBLEN]
    add     x9, x9, x10
    str     x9, [x29, #LOC_OBLEN]
    add     x24, x24, x10
    sub     x25, x25, x10
    b       .op_l
.op_ret:
    ldr     x30, [sp, #16]
    ldp     x24, x25, [sp], #32
    ret

// ob_flush(): write OBUF to stdout and reset it.
ob_flush:
    ldr     x2, [x29, #LOC_OBLEN]
    cbz     x2, .obf_ret
    stp     x29, x30, [sp, #-16]!
    mov     x0, #STDOUT
    add     x1, x29, #OBUFOFF
    bl      uolt_write
    str     xzr, [x29, #LOC_OBLEN]
    ldp     x29, x30, [sp], #16
.obf_ret:
    ret

nl_char:   .byte 0x0a
err_nomem: .asciz "uolt-sort: out of memory\n"
