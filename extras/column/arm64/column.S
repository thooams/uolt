// extras/column/arm64/column.S - uolt-column: align whitespace-columned stdin
// into a padded table, like `column -t`. aarch64.
//
// Reads stdin, splits each line into fields on runs of blanks, and prints the
// fields aligned into columns: each field padded to the widest in its column,
// columns separated by two blanks (column -t). The last field is not padded, blank
// lines are dropped, widths are measured in UTF-8 code points. Only `-t` mode is
// implemented (a `-t` argument is accepted and ignored). Mirrors the x86_64 body.
//
// A UOLT *extra* (util-linux/BSD, not POSIX). The whole of stdin is slurped into a
// growable anonymous mmap region, a first pass computes column widths, a second
// re-scans and emits through a 64 KiB output buffer. No heap (Principle IV).
//
// Callee-saved: x19 = input buffer; x20 = output buffer; x21 = column-width array;
//   x22 = input fill then column index; x23 = line cursor. Locals off x29;
//   .nomem/.too_many reset sp via x29.

#include "uolt.inc"

.set STDIN,  0
.set STDOUT, 1
.set STDERR, 2

.set ICAP_START, 0x10000
.set OBUF_CAP,   0x10000
.set COLMAX,     1024
.set COLW_BYTES, 8192          // COLMAX * 8
.set COLGAP,     2

.set LOC_ICAP, 56
.set LOC_N,    64
.set LOC_END,  72
.set LOC_OLEN, 80
.set LOC_NC,   88
.set LOC_NB,   96
.set LOC_LEND, 104
.set LOC_P,    112
.set LOC_FS,   120
.set LOC_FE,   128
.set LOC_CFS,  136
.set LOC_CFE,  144

.text
.globl uolt_main
uolt_main:
    sub     sp, sp, #160
    mov     x29, sp
    str     x30, [x29, #0]
    stp     x19, x20, [x29, #16]
    stp     x21, x22, [x29, #32]
    str     x23, [x29, #48]

    mov     x0, #ICAP_START
    bl      uolt_mmap_anon
    cmp     x0, #0
    b.mi    .nomem
    mov     x19, x0                    // input buffer
    mov     x9, #ICAP_START
    str     x9, [x29, #LOC_ICAP]
    mov     x0, #OBUF_CAP
    bl      uolt_mmap_anon
    cmp     x0, #0
    b.mi    .nomem
    mov     x20, x0                    // output buffer
    mov     x0, #COLW_BYTES
    bl      uolt_mmap_anon
    cmp     x0, #0
    b.mi    .nomem
    mov     x21, x0                    // column-width array (zero-filled)
    str     xzr, [x29, #LOC_OLEN]

    // ---- slurp all of stdin into the growable input region ----
    mov     x22, #0                    // fill count
.rd:
    ldr     x0, [x29, #LOC_ICAP]
    sub     x0, x0, x22
    cbnz    x0, .rd_have
    bl      grow_input
    ldr     x0, [x29, #LOC_ICAP]
    sub     x0, x0, x22
.rd_have:
    mov     x2, x0
    mov     x0, #STDIN
    add     x1, x19, x22
    bl      uolt_read
    cmp     x0, #0
    b.le    .eof
    add     x22, x22, x0
    b       .rd
.eof:
    str     x22, [x29, #LOC_N]
    add     x9, x19, x22
    str     x9, [x29, #LOC_END]

    // ---- pass 1: per-column display widths ----
    mov     x23, x19                   // cur = start of input
.p1_line:
    ldr     x9, [x29, #LOC_END]
    cmp     x23, x9
    b.hs    .p1_done
    mov     x0, x23
    ldr     x1, [x29, #LOC_END]
.p1_fe:
    cmp     x0, x1
    b.hs    .p1_have
    ldrb    w2, [x0]
    cmp     w2, #0x0a
    b.eq    .p1_have
    add     x0, x0, #1
    b       .p1_fe
.p1_have:
    str     x0, [x29, #LOC_LEND]
    str     x23, [x29, #LOC_P]
    mov     x22, #0                    // column index
.p1_fld:
    bl      next_field
    cmn     x0, #1
    b.eq    .p1_lineend                // -1: no more fields
    bl      dispw                      // x0 = display width (x0=start, x1=end)
    cmp     x22, #COLMAX
    b.hs    .too_many
    ldr     x9, [x21, x22, lsl #3]
    cmp     x0, x9
    b.ls    .p1_nomax
    str     x0, [x21, x22, lsl #3]
.p1_nomax:
    add     x22, x22, #1
    b       .p1_fld
.p1_lineend:
    ldr     x0, [x29, #LOC_LEND]
    ldr     x9, [x29, #LOC_END]
    cmp     x0, x9
    b.hs    .p1_adv
    add     x0, x0, #1
.p1_adv:
    mov     x23, x0
    b       .p1_line
.p1_done:

    // ---- pass 2: emit the aligned columns ----
    mov     x23, x19
.row_l:
    ldr     x9, [x29, #LOC_END]
    cmp     x23, x9
    b.hs    .done
    mov     x0, x23
    ldr     x1, [x29, #LOC_END]
.rl_fe:
    cmp     x0, x1
    b.hs    .rl_have
    ldrb    w2, [x0]
    cmp     w2, #0x0a
    b.eq    .rl_have
    add     x0, x0, #1
    b       .rl_fe
.rl_have:
    str     x0, [x29, #LOC_LEND]
    mov     x2, x23                    // blank-line check
.rl_chk:
    cmp     x2, x0
    b.hs    .rl_skip
    ldrb    w3, [x2]
    cmp     w3, #' '
    b.eq    .rl_chk_adv
    cmp     w3, #0x09
    b.ne    .rl_emit
.rl_chk_adv:
    add     x2, x2, #1
    b       .rl_chk
.rl_skip:
    ldr     x0, [x29, #LOC_LEND]
    ldr     x9, [x29, #LOC_END]
    cmp     x0, x9
    b.hs    .rl_adv
    add     x0, x0, #1
.rl_adv:
    mov     x23, x0
    b       .row_l
.rl_emit:
    str     x23, [x29, #LOC_P]         // field cursor = line start
    mov     x22, #0                    // column index
    bl      next_field                 // first field (line is non-blank)
    str     x0, [x29, #LOC_CFS]
    str     x1, [x29, #LOC_CFE]
.cell_l:
    bl      next_field                 // peek the next field
    cmn     x0, #1
    b.eq    .cell_last
    str     x0, [x29, #LOC_FS]         // save the peek
    str     x1, [x29, #LOC_FE]
    ldr     x1, [x29, #LOC_CFS]        // emit the held field
    ldr     x2, [x29, #LOC_CFE]
    sub     x2, x2, x1
    bl      ob_put
    ldr     x0, [x29, #LOC_CFS]
    ldr     x1, [x29, #LOC_CFE]
    bl      dispw                      // held field display width
    ldr     x9, [x21, x22, lsl #3]
    sub     x9, x9, x0                 // pad to the column width
    add     x9, x9, #COLGAP
    mov     x0, x9
    bl      ob_sp
    add     x22, x22, #1
    ldr     x9, [x29, #LOC_FS]         // promote the peek to held
    str     x9, [x29, #LOC_CFS]
    ldr     x9, [x29, #LOC_FE]
    str     x9, [x29, #LOC_CFE]
    b       .cell_l
.cell_last:
    ldr     x1, [x29, #LOC_CFS]
    ldr     x2, [x29, #LOC_CFE]
    sub     x2, x2, x1
    bl      ob_put
    mov     w0, #0x0a
    bl      ob_putb
    ldr     x0, [x29, #LOC_LEND]
    ldr     x9, [x29, #LOC_END]
    cmp     x0, x9
    b.hs    .cl_adv
    add     x0, x0, #1
.cl_adv:
    mov     x23, x0
    b       .row_l
.done:
    bl      ob_flush
    mov     x0, #0
    b       .ret
.nomem:
    adr     x0, err_nomem
    bl      err_puts
    mov     x0, #1
    b       .ret
.too_many:
    adr     x0, err_many
    bl      err_puts
    mov     x0, #1
.ret:
    mov     sp, x29
    ldr     x30, [x29, #0]
    ldp     x19, x20, [x29, #16]
    ldp     x21, x22, [x29, #32]
    ldr     x23, [x29, #48]
    add     sp, sp, #160
    ret

// grow_input(): double the input buffer, copy the x22 bytes held, unmap the old
// region, update x19 / LOC_ICAP. Preserves x20/x21/x22/x23.
grow_input:
    stp     x29, x30, [sp, #-16]!
    ldr     x0, [x29, #LOC_ICAP]
    add     x0, x0, x0
    str     x0, [x29, #LOC_NC]
    bl      uolt_mmap_anon
    cmp     x0, #0
    b.mi    .nomem
    str     x0, [x29, #LOC_NB]
    mov     x9, #0
.gi_cp:
    cmp     x9, x22
    b.hs    .gi_cpd
    ldrb    w10, [x19, x9]
    strb    w10, [x0, x9]
    add     x9, x9, #1
    b       .gi_cp
.gi_cpd:
    mov     x0, x19
    ldr     x1, [x29, #LOC_ICAP]
    bl      uolt_munmap
    ldr     x19, [x29, #LOC_NB]
    ldr     x9, [x29, #LOC_NC]
    str     x9, [x29, #LOC_ICAP]
    ldp     x29, x30, [sp], #16
    ret

// next_field() -> x0 = field start (or -1 if no more fields), x1 = field end.
// Advances LOC_P. Uses only x0/x1/x2 + locals.
next_field:
    ldr     x0, [x29, #LOC_P]
    ldr     x1, [x29, #LOC_LEND]
.nf_ws:
    cmp     x0, x1
    b.hs    .nf_none
    ldrb    w2, [x0]
    cmp     w2, #' '
    b.eq    .nf_adv
    cmp     w2, #0x09
    b.ne    .nf_start
.nf_adv:
    add     x0, x0, #1
    b       .nf_ws
.nf_start:
    str     x0, [x29, #LOC_FS]
.nf_nb:
    cmp     x0, x1
    b.hs    .nf_end
    ldrb    w2, [x0]
    cmp     w2, #' '
    b.eq    .nf_end
    cmp     w2, #0x09
    b.eq    .nf_end
    add     x0, x0, #1
    b       .nf_nb
.nf_end:
    str     x0, [x29, #LOC_P]
    mov     x1, x0
    ldr     x0, [x29, #LOC_FS]
    ret
.nf_none:
    str     x0, [x29, #LOC_P]
    mov     x0, #-1
    ret

// dispw(x0 = start, x1 = end) -> x0 = number of UTF-8 code points (non-continuation
// bytes). Leaf.
dispw:
    mov     x2, x0                     // cursor
    mov     x0, #0                     // count
.dw_l:
    cmp     x2, x1
    b.hs    .dw_done
    ldrb    w3, [x2]
    lsr     w3, w3, #6
    cmp     w3, #2                     // 10xxxxxx continuation byte
    b.eq    .dw_skip
    add     x0, x0, #1
.dw_skip:
    add     x2, x2, #1
    b       .dw_l
.dw_done:
    ret

// ---- buffered output. x20 = buffer, LOC_OLEN = fill. ----

ob_flush:
    ldr     x2, [x29, #LOC_OLEN]
    cbz     x2, .obf_ret
    stp     x29, x30, [sp, #-16]!
    mov     x0, #STDOUT
    mov     x1, x20
    bl      uolt_write
    str     xzr, [x29, #LOC_OLEN]
    ldp     x29, x30, [sp], #16
.obf_ret:
    ret

// ob_put(x1 = ptr, x2 = len): append len bytes, flushing as the buffer fills.
// x24 = ptr, x25 = len.
ob_put:
    stp     x24, x25, [sp, #-32]!
    str     x30, [sp, #16]
    mov     x24, x1
    mov     x25, x2
.op_l:
    cbz     x25, .op_done
    mov     x9, #OBUF_CAP
    ldr     x10, [x29, #LOC_OLEN]
    sub     x9, x9, x10                // space
    cbnz    x9, .op_room
    bl      ob_flush
    mov     x9, #OBUF_CAP
    mov     x10, #0
.op_room:
    cmp     x9, x25
    b.ls    .op_cap
    mov     x9, x25                    // copy = min(space, len)
.op_cap:
    add     x11, x20, x10              // dst = obuf + olen
    mov     x12, #0
.op_cp:
    cmp     x12, x9
    b.hs    .op_cpd
    ldrb    w13, [x24, x12]
    strb    w13, [x11, x12]
    add     x12, x12, #1
    b       .op_cp
.op_cpd:
    ldr     x10, [x29, #LOC_OLEN]
    add     x10, x10, x9
    str     x10, [x29, #LOC_OLEN]
    add     x24, x24, x9
    sub     x25, x25, x9
    b       .op_l
.op_done:
    ldr     x30, [sp, #16]
    ldp     x24, x25, [sp], #32
    ret

// ob_putb(w0 = byte): append a single byte.
ob_putb:
    ldr     x9, [x29, #LOC_OLEN]
    cmp     x9, #OBUF_CAP
    b.lo    .opb_store
    stp     x0, x30, [sp, #-16]!
    bl      ob_flush
    ldp     x0, x30, [sp], #16
.opb_store:
    ldr     x9, [x29, #LOC_OLEN]
    strb    w0, [x20, x9]
    add     x9, x9, #1
    str     x9, [x29, #LOC_OLEN]
    ret

// ob_sp(x0 = count): append count blanks.
ob_sp:
    cbz     x0, .osp_ret
    stp     x0, x30, [sp, #-16]!
    mov     w0, #' '
    bl      ob_putb
    ldp     x0, x30, [sp], #16
    sub     x0, x0, #1
    b       ob_sp
.osp_ret:
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

err_many:  .asciz "uolt-column: too many columns\n"
err_nomem: .asciz "uolt-column: out of memory\n"
