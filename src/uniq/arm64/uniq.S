// src/uniq/arm64/uniq.S - the POSIX `uniq` utility, aarch64.
//
// uniq [-c] [-d] [-u] [-i] [-f N] [-s N] [file]: collapse adjacent identical
// lines. -c prefixes repeat counts; -d only repeated runs; -u only unique runs;
// -i folds case; -f N skips leading fields; -s N skips leading chars when
// comparing (the whole line is still printed). Mirrors the x86_64 body.
//
// Input is streamed and split into lines; the current run's representative is kept
// in a separate buffer with its count. Both buffers are mmap'd regions that GROW
// on demand (double, copy, munmap) so a line of any length streams in constant
// memory (Principle IV permits an explicit, failure-checked mmap here).
//
// Callee-saved: x19 = input buffer; x20 = prev-line buffer; x21 = argc-count then
//   fd; x22 = &argv walk then fill; x23 = token then line start. Locals off x29;
//   .nomem resets sp via x29 so a grow failure at any depth unwinds.

#include "uolt.inc"

.set STDIN,  0
.set STDOUT, 1
.set STDERR, 2
.set O_RDONLY, 0
.set ICAP_START, 0x10000
.set PCAP_START, 0x10000

.set LOC_FLAGS, 64              // bit0 -c, bit1 -d, bit2 -u, bit3 -i
.set LOC_HAVE,  72
.set LOC_PLEN,  80
.set LOC_COUNT, 88
.set LOC_CH,    96
.set LOC_SKIPF, 104
.set LOC_SKIPS, 112
.set LOC_ICAP,  120
.set LOC_PCAP,  128
.set LOC_NC,    136
.set LOC_NB,    144
.set LOC_CNT,   152            // 24-byte count scratch
.set FRAME,     176

.text
.globl uolt_main
uolt_main:
    sub     sp, sp, #FRAME
    mov     x29, sp
    str     x30, [x29, #0]
    stp     x19, x20, [x29, #16]
    stp     x21, x22, [x29, #32]
    str     x23, [x29, #48]

    sub     x21, x0, #1                // argc - 1
    add     x22, x1, #8                // &argv[1]
    mov     x0, #ICAP_START
    bl      uolt_mmap_anon
    cmp     x0, #0
    b.mi    .nomem
    mov     x19, x0                    // input block buffer
    mov     x9, #ICAP_START
    str     x9, [x29, #LOC_ICAP]
    mov     x0, #PCAP_START
    bl      uolt_mmap_anon
    cmp     x0, #0
    b.mi    .nomem
    mov     x20, x0                    // prev-line buffer
    mov     x9, #PCAP_START
    str     x9, [x29, #LOC_PCAP]
    str     xzr, [x29, #LOC_FLAGS]
    str     xzr, [x29, #LOC_HAVE]
    str     xzr, [x29, #LOC_COUNT]
    str     xzr, [x29, #LOC_SKIPF]
    str     xzr, [x29, #LOC_SKIPS]
.opt:
    cbz     x21, .input
    ldr     x23, [x22]
    ldrb    w9, [x23]
    cmp     w9, #'-'
    b.ne    .input
    ldrb    w9, [x23, #1]
    cbz     w9, .input                 // "-" = stdin operand
    cmp     w9, #'-'
    b.eq    .ddash
    cmp     w9, #'f'
    b.eq    .opt_f
    cmp     w9, #'s'
    b.eq    .opt_s
    add     x3, x23, #1
    mov     x4, x3
.v:
    ldrb    w9, [x3]
    cbz     w9, .apply
    cmp     w9, #'c'
    b.eq    .v_ok
    cmp     w9, #'d'
    b.eq    .v_ok
    cmp     w9, #'u'
    b.eq    .v_ok
    cmp     w9, #'i'
    b.eq    .v_ok
    b       .input
.v_ok:
    add     x3, x3, #1
    b       .v
.apply:
    mov     x3, x4
.ap:
    ldrb    w9, [x3]
    cbz     w9, .apd
    cmp     w9, #'c'
    b.ne    .ap2
    ldr     x10, [x29, #LOC_FLAGS]
    orr     x10, x10, #1
    str     x10, [x29, #LOC_FLAGS]
.ap2:
    cmp     w9, #'d'
    b.ne    .ap3
    ldr     x10, [x29, #LOC_FLAGS]
    orr     x10, x10, #2
    str     x10, [x29, #LOC_FLAGS]
.ap3:
    cmp     w9, #'u'
    b.ne    .ap4
    ldr     x10, [x29, #LOC_FLAGS]
    orr     x10, x10, #4
    str     x10, [x29, #LOC_FLAGS]
.ap4:
    cmp     w9, #'i'
    b.ne    .ap9
    ldr     x10, [x29, #LOC_FLAGS]
    orr     x10, x10, #8
    str     x10, [x29, #LOC_FLAGS]
.ap9:
    add     x3, x3, #1
    b       .ap
.apd:
    add     x22, x22, #8
    sub     x21, x21, #1
    b       .opt
.ddash:
    ldrb    w9, [x23, #2]
    cbnz    w9, .input
    add     x22, x22, #8
    sub     x21, x21, #1
    b       .input
.opt_f:
    add     x0, x23, #2                // "-fN" attached, or "-f" then next arg
    ldrb    w9, [x0]
    cbnz    w9, .opt_f_go
    add     x22, x22, #8
    sub     x21, x21, #1
    cbz     x21, .input
    ldr     x0, [x22]
.opt_f_go:
    bl      parse_uint
    str     x0, [x29, #LOC_SKIPF]
    add     x22, x22, #8
    sub     x21, x21, #1
    b       .opt
.opt_s:
    add     x0, x23, #2
    ldrb    w9, [x0]
    cbnz    w9, .opt_s_go
    add     x22, x22, #8
    sub     x21, x21, #1
    cbz     x21, .input
    ldr     x0, [x22]
.opt_s_go:
    bl      parse_uint
    str     x0, [x29, #LOC_SKIPS]
    add     x22, x22, #8
    sub     x21, x21, #1
    b       .opt

.input:
    cbz     x21, .use_stdin
    ldr     x0, [x22]
    mov     x1, #O_RDONLY
    mov     x2, #0
    bl      uolt_open
    cmp     x0, #0
    b.mi    .open_err
    mov     x21, x0                    // fd
    b       .run
.use_stdin:
    mov     x21, #STDIN
.run:
    mov     x22, #0                    // fill
.rd:
    ldr     x0, [x29, #LOC_ICAP]
    sub     x0, x0, x22                // space left in the input buffer
    cbnz    x0, .rd_have
    bl      grow_input                 // one line filled it: grow, keep reading
    ldr     x0, [x29, #LOC_ICAP]
    sub     x0, x0, x22
.rd_have:
    mov     x2, x0
    mov     x0, x21
    add     x1, x19, x22
    bl      uolt_read
    cmp     x0, #0
    b.le    .eof
    add     x22, x22, x0
    mov     x23, #0                    // start
.scan:
    mov     x9, x23
.find:
    cmp     x9, x22
    b.hs    .compact
    ldrb    w10, [x19, x9]
    cmp     w10, #0x0a
    b.eq    .line
    add     x9, x9, #1
    b       .find
.line:
    add     x0, x19, x23
    sub     x1, x9, x23
    add     x23, x9, #1
    bl      take_line
    b       .scan
.compact:
    sub     x11, x22, x23
    mov     x9, #0
.cp:
    cmp     x9, x11
    b.hs    .cpd
    add     x12, x19, x23
    ldrb    w13, [x12, x9]
    strb    w13, [x19, x9]
    add     x9, x9, #1
    b       .cp
.cpd:
    mov     x22, x11
    b       .rd
.eof:
    cbz     x22, .flush_last
    mov     x0, x19
    mov     x1, x22
    bl      take_line
.flush_last:
    ldr     x9, [x29, #LOC_HAVE]
    cbz     x9, .fin
    bl      flush_run
.fin:
    mov     x0, #0
    b       .ret
.open_err:
    adr     x0, err_pre
    bl      err_puts
    ldr     x0, [x22]
    bl      err_puts
    adr     x0, err_suf
    bl      err_puts
    mov     x0, #1
.ret:
    mov     sp, x29
    ldr     x30, [x29, #0]
    ldp     x19, x20, [x29, #16]
    ldp     x21, x22, [x29, #32]
    ldr     x23, [x29, #48]
    add     sp, sp, #FRAME
    ret
.nomem:
    adr     x0, err_nomem
    bl      err_puts
    mov     x0, #1
    b       .ret

// grow_input(): double the input buffer, copy the x22 bytes held, unmap the old
// one, update x19 / LOC_ICAP. Preserves x20/x21/x22/x23.
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

// ensure_prev(x0 = needed bytes): make the prev-line buffer at least that large
// (old contents are discarded). Preserves take_line's x24/x25/x26.
ensure_prev:
    stp     x29, x30, [sp, #-16]!
    ldr     x9, [x29, #LOC_PCAP]
    cmp     x9, x0
    b.hs    .ep_ok
    mov     x10, x9
.ep_dbl:
    add     x10, x10, x10
    cmp     x10, x0
    b.lo    .ep_dbl
    str     x10, [x29, #LOC_NC]
    mov     x0, x20                    // free the old buffer
    ldr     x1, [x29, #LOC_PCAP]
    bl      uolt_munmap
    ldr     x0, [x29, #LOC_NC]
    bl      uolt_mmap_anon
    cmp     x0, #0
    b.mi    .nomem
    mov     x20, x0
    ldr     x9, [x29, #LOC_NC]
    str     x9, [x29, #LOC_PCAP]
.ep_ok:
    ldp     x29, x30, [sp], #16
    ret

// take_line(x0 = line ptr, x1 = length): compare with the current run; extend or
// flush + start a new one. x24 = line ptr, x25 = length, x26 = suffix length.
take_line:
    sub     sp, sp, #48
    stp     x24, x25, [sp, #0]
    stp     x26, x30, [sp, #16]
    mov     x24, x0
    mov     x25, x1
    ldr     x9, [x29, #LOC_HAVE]
    cbz     x9, .tl_new
    mov     x0, x20                    // prev comparison start
    ldr     x1, [x29, #LOC_PLEN]
    bl      skip_offset
    str     x0, [sp, #32]              // prev offset
    mov     x0, x24                    // current comparison start
    mov     x1, x25
    bl      skip_offset
    str     x0, [sp, #40]              // cur offset
    ldr     x9, [x29, #LOC_PLEN]
    ldr     x10, [sp, #32]
    sub     x9, x9, x10                // prev suffix length
    sub     x26, x25, x0               // current suffix length
    cmp     x9, x26
    b.ne    .tl_diff                   // suffix lengths differ
    add     x11, x20, x10              // prev suffix base
    ldr     x12, [sp, #40]
    add     x12, x24, x12              // current suffix base
    mov     x13, #0
.tl_cmp:
    cmp     x13, x26
    b.eq    .tl_same
    ldrb    w14, [x11, x13]
    ldrb    w15, [x12, x13]
    ldr     x9, [x29, #LOC_FLAGS]
    tbz     x9, #3, .tl_c2             // -i
    cmp     w14, #'A'
    b.lo    .tl_a2
    cmp     w14, #'Z'
    b.hi    .tl_a2
    add     w14, w14, #0x20
.tl_a2:
    cmp     w15, #'A'
    b.lo    .tl_c2
    cmp     w15, #'Z'
    b.hi    .tl_c2
    add     w15, w15, #0x20
.tl_c2:
    cmp     w14, w15
    b.ne    .tl_diff
    add     x13, x13, #1
    b       .tl_cmp
.tl_same:
    ldr     x9, [x29, #LOC_COUNT]
    add     x9, x9, #1
    str     x9, [x29, #LOC_COUNT]
    b       .tl_ret
.tl_diff:
    bl      flush_run
.tl_new:
    mov     x0, x25                    // needed = line length
    bl      ensure_prev
    str     x25, [x29, #LOC_PLEN]
    mov     x9, #0
.tl_copy:
    cmp     x9, x25
    b.hs    .tl_copydone
    ldrb    w10, [x24, x9]
    strb    w10, [x20, x9]
    add     x9, x9, #1
    b       .tl_copy
.tl_copydone:
    mov     x9, #1
    str     x9, [x29, #LOC_HAVE]
    mov     x9, #1
    str     x9, [x29, #LOC_COUNT]
.tl_ret:
    ldp     x24, x25, [sp, #0]
    ldp     x26, x30, [sp, #16]
    add     sp, sp, #48
    ret

// flush_run(): emit the current run per the flags. Saves lr.
flush_run:
    stp     x29, x30, [sp, #-16]!
    ldr     x9, [x29, #LOC_FLAGS]
    ldr     x10, [x29, #LOC_COUNT]
    tbz     x9, #1, .fr_c1             // -d: only runs with count > 1
    cmp     x10, #1
    b.le    .fr_ret
.fr_c1:
    tbz     x9, #2, .fr_c2             // -u: only runs with count == 1
    cmp     x10, #1
    b.ne    .fr_ret
.fr_c2:
    tbz     x9, #0, .fr_line           // -c: count prefix
    mov     x0, x10
    bl      put_count
.fr_line:
    mov     x0, #STDOUT
    mov     x1, x20
    ldr     x2, [x29, #LOC_PLEN]
    bl      uolt_write
    mov     w9, #0x0a
    strb    w9, [x29, #LOC_CH]
    mov     x0, #STDOUT
    add     x1, x29, #LOC_CH
    mov     x2, #1
    bl      uolt_write
.fr_ret:
    ldp     x29, x30, [sp], #16
    ret

// put_count(x0 = value >= 1): write the decimal value and a trailing space.
put_count:
    add     x9, x29, #LOC_CNT
    add     x9, x9, #22                // trailing space position
    mov     w10, #' '
    strb    w10, [x9]
    mov     x11, x0
    mov     x12, #10
.pc_l:
    sub     x9, x9, #1
    udiv    x13, x11, x12
    msub    x14, x13, x12, x11
    add     w14, w14, #'0'
    strb    w14, [x9]
    mov     x11, x13
    cbnz    x11, .pc_l
    add     x10, x29, #LOC_CNT
    add     x10, x10, #23              // one past the space
    sub     x2, x10, x9
    mov     x1, x9
    mov     x0, #STDOUT
    b       uolt_write

// skip_offset(x0 = line ptr, x1 = length) -> x0 = comparison start after skipping
// -f fields and -s chars. Clobbers x0/x9/x10/x11 only.
skip_offset:
    mov     x9, #0                     // i
    ldr     x10, [x29, #LOC_SKIPF]
.so_field:
    cbz     x10, .so_chars
.so_bl:
    cmp     x9, x1
    b.hs    .so_done
    ldrb    w11, [x0, x9]
    cmp     w11, #' '
    b.eq    .so_bladv
    cmp     w11, #0x09
    b.ne    .so_nb
.so_bladv:
    add     x9, x9, #1
    b       .so_bl
.so_nb:
    cmp     x9, x1
    b.hs    .so_done
    ldrb    w11, [x0, x9]
    cmp     w11, #' '
    b.eq    .so_fdone
    cmp     w11, #0x09
    b.eq    .so_fdone
    add     x9, x9, #1
    b       .so_nb
.so_fdone:
    sub     x10, x10, #1
    b       .so_field
.so_chars:
    ldr     x10, [x29, #LOC_SKIPS]
.so_cl:
    cbz     x10, .so_done
    cmp     x9, x1
    b.hs    .so_done
    add     x9, x9, #1
    sub     x10, x10, #1
    b       .so_cl
.so_done:
    mov     x0, x9
    ret

// parse_uint(x0 = ASCIZ) -> x0 = leading unsigned decimal. Leaf.
parse_uint:
    mov     x1, x0
    mov     x0, #0
.pu_l:
    ldrb    w2, [x1]
    sub     w2, w2, #'0'
    cmp     w2, #9
    b.hi    .pu_d
    mov     x3, #10
    mul     x0, x0, x3
    add     x0, x0, w2, uxtw
    add     x1, x1, #1
    b       .pu_l
.pu_d:
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

err_pre:   .asciz "uolt-uniq: "
err_suf:   .asciz ": cannot open\n"
err_nomem: .asciz "uolt-uniq: out of memory\n"
