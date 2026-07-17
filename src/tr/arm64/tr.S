// src/tr/arm64/tr.S - the `tr` utility (translate / delete), aarch64.
//
// tr set1 set2   translate bytes in set1 to the matching byte of set2
// tr -d set1     delete bytes in set1
// tr -s set1     squeeze repeated bytes in set1 to one
//
// -c (or -C) complements set1. Options combine (-cd, -cs, -ds ...). Each set is a
// sequence of literal bytes and ranges (a-z). For translation a byte in set1 maps
// to set2's byte at the same index, or set2's last byte if set2 is shorter.
// Backslash escapes are out of scope in v1. Mirrors the x86_64 body.
//
// A 256-entry translate table, a 256-entry delete flag, a 256-entry squeeze flag
// (and a 256-entry set1-membership scratch) are built on the stack (no heap,
// Principle IV). Input is transformed block by block through a 64 KB buffer; the
// last output byte is carried across blocks so squeeze runs span block boundaries.
//
// Callee-saved roles: x19 = I/O buffer (in at x19, out at x19+BUFSZ); x20 = tables
//   (map[256] @ +0, del[256] @ +256, sq[256] @ +512, in1[256] @ +768); x21 =
//   argc-1 then bytes-in; x22 = &argv walk then out length; x23 = token ptr then
//   in index / set count; x24 = len2. Locals off x29.

#include "uolt.inc"

.set STDIN,  0
.set STDOUT, 1
.set STDERR, 2
.set BUFSZ,  65536

.set LOC_DEL,  56
.set LOC_SQ,   64
.set LOC_PREV, 72
.set LOC_C,    80

.text
.globl uolt_main
uolt_main:
    sub     sp, sp, #96
    mov     x29, sp
    stp     x19, x20, [sp, #0]
    stp     x21, x22, [sp, #16]
    stp     x23, x24, [sp, #32]
    str     x30, [sp, #48]
    sub     sp, sp, #131072            // 2*BUFSZ
    sub     sp, sp, #1088              // + 1024 tables + 64 slack
    mov     x19, sp                    // I/O buffer base
    add     x20, x19, #131072          // tables region
    str     xzr, [x29, #LOC_DEL]
    str     xzr, [x29, #LOC_SQ]
    mov     x9, #-1
    str     x9, [x29, #LOC_PREV]
    str     xzr, [x29, #LOC_C]

    sub     x21, x0, #1                // argc - 1
    add     x22, x1, #8                // &argv[1]

    // Leading options: any token like -d, -s, -ds, -sd (letters d/s/c/C only).
.opt:
    cbz     x21, .init
    ldr     x23, [x22]
    ldrb    w9, [x23]
    cmp     w9, #'-'
    b.ne    .init
    ldrb    w9, [x23, #1]
    cbz     w9, .init                  // "-" is an operand, not a flag
    cmp     w9, #'-'
    b.eq    .ddash
    add     x4, x23, #1                // validate every letter is d/s/c/C
.ov:
    ldrb    w9, [x4]
    cbz     w9, .oapply
    cmp     w9, #'d'
    b.eq    .ov_ok
    cmp     w9, #'s'
    b.eq    .ov_ok
    cmp     w9, #'c'
    b.eq    .ov_ok
    cmp     w9, #'C'
    b.eq    .ov_ok
    b       .init                      // unknown letter -> treat token as a set
.ov_ok:
    add     x4, x4, #1
    b       .ov
.oapply:
    add     x4, x23, #1
.oa:
    ldrb    w9, [x4]
    cbz     w9, .odone
    cmp     w9, #'d'
    b.ne    .oa2
    mov     x10, #1
    str     x10, [x29, #LOC_DEL]
.oa2:
    cmp     w9, #'s'
    b.ne    .oa3
    mov     x10, #1
    str     x10, [x29, #LOC_SQ]
.oa3:
    cmp     w9, #'c'
    b.eq    .oa_c
    cmp     w9, #'C'
    b.ne    .oa5
.oa_c:
    mov     x10, #1
    str     x10, [x29, #LOC_C]
.oa5:
    add     x4, x4, #1
    b       .oa
.odone:
    add     x22, x22, #8
    sub     x21, x21, #1
    b       .opt
.ddash:
    ldrb    w9, [x23, #2]
    cbnz    w9, .init
    add     x22, x22, #8
    sub     x21, x21, #1
.init:
    // Identity map, clear delete table, clear squeeze table.
    mov     x9, #0
.id:
    strb    w9, [x20, x9]              // map[c] = c
    add     x10, x20, x9
    strb    wzr, [x10, #256]          // del[c] = 0
    strb    wzr, [x10, #512]          // sq[c]  = 0
    add     x9, x9, #1
    cmp     x9, #256
    b.ne    .id

    ldr     x9, [x29, #LOC_DEL]
    cbnz    x9, .build_delete

    // No delete. Two sets -> translate; one set with -s -> squeeze-only.
    cmp     x21, #2
    b.ge    .translate2
    cmp     x21, #1
    b.lt    .usage
    ldr     x9, [x29, #LOC_SQ]
    cbz     x9, .usage
    ldr     x0, [x22]                  // squeeze-only: mark sq from set1
    add     x1, x19, #BUFSZ
    bl      expand_set
    mov     x23, x0
    add     x0, x19, #BUFSZ
    mov     x1, x23
    bl      mark_sq
    ldr     x9, [x29, #LOC_C]
    cbz     x9, .run
    mov     x9, #0
    add     x11, x20, #512
.sqo_inv:
    ldrb    w10, [x11, x9]             // -c: squeeze the complement
    eor     w10, w10, #1
    strb    w10, [x11, x9]
    add     x9, x9, #1
    cmp     x9, #256
    b.ne    .sqo_inv
    b       .run

.translate2:
    ldr     x0, [x22]                  // set1 -> expand into out-buffer area
    add     x1, x19, #BUFSZ
    bl      expand_set
    mov     x23, x0                    // len1
    ldr     x0, [x22, #8]              // set2 -> expand into I/O buffer
    mov     x1, x19
    bl      expand_set
    mov     x24, x0                    // len2
    cbz     x24, .usage
    ldr     x9, [x29, #LOC_C]
    cbnz    x9, .translate_c
    // map[set1[i]] = set2[min(i, len2-1)]
    mov     x9, #0
.mp:
    cmp     x9, x23
    b.hs    .mp_done
    add     x10, x19, #BUFSZ
    ldrb    w11, [x10, x9]             // set1[i]
    mov     x12, x9                    // j = min(i, len2-1)
    cmp     x12, x24
    b.lo    .mp_j
    sub     x12, x24, #1
.mp_j:
    ldrb    w13, [x19, x12]            // set2[j]
    strb    w13, [x20, x11]           // map[set1[i]] = set2[j]
    add     x9, x9, #1
    b       .mp

.translate_c:
    // -c: map every byte NOT in set1, ascending, to set2 (last byte beyond len2).
    mov     x9, #0
    add     x10, x20, #768
.tc_clr:
    strb    wzr, [x10, x9]
    add     x9, x9, #1
    cmp     x9, #256
    b.ne    .tc_clr
    mov     x9, #0
.tc_mark:
    cmp     x9, x23                    // len1
    b.hs    .tc_map
    add     x11, x19, #BUFSZ
    ldrb    w12, [x11, x9]
    add     x10, x20, #768
    mov     w13, #1
    strb    w13, [x10, x12]
    add     x9, x9, #1
    b       .tc_mark
.tc_map:
    mov     x9, #0                     // c
    mov     x11, #0                    // k = index among complement bytes
.tc_loop:
    cmp     x9, #256
    b.hs    .mp_done
    add     x10, x20, #768
    ldrb    w12, [x10, x9]
    cbnz    w12, .tc_next              // c in set1 -> keep identity map
    mov     x12, x11                   // j = min(k, len2-1)
    cmp     x12, x24
    b.lo    .tc_j
    sub     x12, x24, #1
.tc_j:
    ldrb    w13, [x19, x12]
    strb    w13, [x20, x9]
    add     x11, x11, #1
.tc_next:
    add     x9, x9, #1
    b       .tc_loop
.mp_done:
    ldr     x9, [x29, #LOC_SQ]
    cbz     x9, .run
    mov     x0, x19                    // squeeze set = set2
    mov     x1, x24
    bl      mark_sq
    b       .run

.build_delete:
    cmp     x21, #1
    b.lt    .usage
    ldr     x0, [x22]
    add     x1, x19, #BUFSZ
    bl      expand_set
    mov     x23, x0
    mov     x9, #0
.del:
    cmp     x9, x23
    b.hs    .del_done
    add     x10, x19, #BUFSZ
    ldrb    w11, [x10, x9]
    add     x12, x20, #256
    mov     w13, #1
    strb    w13, [x12, x11]           // del[set1[i]] = 1
    add     x9, x9, #1
    b       .del
.del_done:
    ldr     x9, [x29, #LOC_C]
    cbz     x9, .del_nc
    mov     x9, #0
    add     x10, x20, #256
.del_inv:
    ldrb    w11, [x10, x9]             // -c: delete the complement of set1
    eor     w11, w11, #1
    strb    w11, [x10, x9]
    add     x9, x9, #1
    cmp     x9, #256
    b.ne    .del_inv
.del_nc:
    // -d with a second set squeezes that set (tr -ds set1 set2).
    ldr     x9, [x29, #LOC_SQ]
    cbz     x9, .run
    cmp     x21, #2
    b.lt    .run
    ldr     x0, [x22, #8]
    mov     x1, x19
    bl      expand_set
    mov     x23, x0
    mov     x0, x19
    mov     x1, x23
    bl      mark_sq

.run:
    // Transform stdin -> stdout, block by block. in at x19, out at x19+BUFSZ.
.rd:
    mov     x0, #STDIN
    mov     x1, x19
    mov     x2, #BUFSZ
    bl      uolt_read
    cmp     x0, #0
    b.le    .done
    mov     x21, x0                    // bytes in
    mov     x23, #0                    // in index
    mov     x22, #0                    // out length
.tx:
    cmp     x23, x21
    b.hs    .flush
    ldrb    w9, [x19, x23]
    ldr     x10, [x29, #LOC_DEL]
    cbz     x10, .tx_map
    add     x11, x20, #256
    ldrb    w12, [x11, x9]
    cbnz    w12, .tx_skip              // deleted
    mov     w13, w9
    b       .tx_emit
.tx_map:
    ldrb    w13, [x20, x9]             // translated byte
.tx_emit:
    ldr     x10, [x29, #LOC_SQ]
    cbz     x10, .tx_store
    add     x11, x20, #512
    ldrb    w12, [x11, x13]
    cbz     w12, .tx_store             // not in the squeeze set -> always keep
    ldr     x10, [x29, #LOC_PREV]
    cmp     x13, x10
    b.eq    .tx_skip                   // same as previous output byte -> drop
.tx_store:
    add     x11, x19, #BUFSZ
    strb    w13, [x11, x22]
    add     x22, x22, #1
    str     x13, [x29, #LOC_PREV]
.tx_skip:
    add     x23, x23, #1
    b       .tx
.flush:
    cbz     x22, .rd
    mov     x0, #STDOUT
    add     x1, x19, #BUFSZ
    mov     x2, x22
    bl      uolt_write
    b       .rd
.done:
    mov     x0, #0
    b       .ret
.usage:
    adr     x0, err_usage
    bl      err_puts
    mov     x0, #1
.ret:
    mov     sp, x29
    ldp     x19, x20, [sp, #0]
    ldp     x21, x22, [sp, #16]
    ldp     x23, x24, [sp, #32]
    ldr     x30, [sp, #48]
    add     sp, sp, #96
    ret

// mark_sq(x0 = expanded byte buffer, x1 = count): set sq[buf[i]] = 1 for each.
// No calls, so lr is untouched.
mark_sq:
    mov     x9, #0
    add     x11, x20, #512
.ms_l:
    cmp     x9, x1
    b.hs    .ms_ret
    ldrb    w10, [x0, x9]
    mov     w12, #1
    strb    w12, [x11, x10]
    add     x9, x9, #1
    b       .ms_l
.ms_ret:
    ret

// expand_set(x0 = ASCIZ set, x1 = dest buffer) -> x0 = count (capped at 256).
// Expands ranges like a-z into individual bytes. No calls.
expand_set:
    mov     x3, x0                     // set cursor
    mov     x4, x1                     // dest
    mov     x0, #0                     // count
.xs_loop:
    ldrb    w9, [x3]
    cbz     w9, .xs_done
    cmp     x0, #256
    b.hs    .xs_done
    ldrb    w10, [x3, #1]
    cmp     w10, #'-'
    b.ne    .xs_lit
    ldrb    w11, [x3, #2]
    cbz     w11, .xs_lit               // '-' at end -> literal '-'
.xs_range:
    cmp     x0, #256
    b.hs    .xs_range_done
    strb    w9, [x4, x0]
    add     x0, x0, #1
    cmp     w9, w11
    b.hs    .xs_range_done
    add     w9, w9, #1
    b       .xs_range
.xs_range_done:
    add     x3, x3, #3
    b       .xs_loop
.xs_lit:
    strb    w9, [x4, x0]
    add     x0, x0, #1
    add     x3, x3, #1
    b       .xs_loop
.xs_done:
    ret

// err_puts(x0 = ASCIZ) -> stderr; length via strlen. Saves lr.
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

err_usage: .asciz "uolt-tr: usage: tr [-cs] set1 set2 | tr -[c]d set1 | tr -[c]s set1\n"
