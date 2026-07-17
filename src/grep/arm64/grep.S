// src/grep/arm64/grep.S - the `grep` utility (fixed-string match), aarch64.
//
// grep [-ivncwx] pattern [file...]: print input lines containing `pattern` as a
// literal substring. -i case-insensitive; -v non-matching lines; -n line numbers;
// -c match count only; -w word-boundary match; -x whole-line match. No file -> read
// stdin; >1 file -> "file:" prefix. Fixed-string matcher (like grep -F). Mirrors
// the x86_64 body.
//
// Input read in 64 KB blocks and split on newlines (no heap, Principle IV). Exit
// 0 if any line matched, 1 if none, 2 on error.
//
// Callee-saved: x19 = line buffer; x20 = argc-count then fd; x21 = &argv walk then
//   fill; x22 = token then line start; x23 = multi-file flag. Locals off x29.

#include "uolt.inc"

.set STDIN,  0
.set STDOUT, 1
.set STDERR, 2
.set BUFSZ,  65536

.set LOC_PAT,    48
.set LOC_PATLEN, 56
.set LOC_FLAGS,  64             // bit0 -i, bit1 -v, bit2 -n, bit3 -c, bit4 -w, bit5 -x
.set LOC_NAME,   72
.set LOC_MATCH,  80
.set LOC_ERR,    88
.set LOC_CH,     96
.set LOC_LINENO, 104
.set LOC_COUNT,  112
.set LOC_XLEN,   120
.set LOC_NUM,    128            // 24-byte decimal scratch

.text
.globl uolt_main
uolt_main:
    sub     sp, sp, #160
    mov     x29, sp
    stp     x19, x20, [sp, #0]
    stp     x21, x22, [sp, #16]
    stp     x23, x30, [sp, #32]
    sub     sp, sp, #65536
    mov     x19, sp
    str     xzr, [x29, #LOC_FLAGS]
    str     xzr, [x29, #LOC_MATCH]
    str     xzr, [x29, #LOC_ERR]

    sub     x20, x0, #1
    add     x21, x1, #8
.opt:
    cbz     x20, .usage
    ldr     x22, [x21]
    ldrb    w9, [x22]
    cmp     w9, #'-'
    b.ne    .have_pat
    ldrb    w9, [x22, #1]
    cbz     w9, .have_pat              // "-" alone is a pattern
    cmp     w9, #'-'
    b.eq    .ddash
    add     x3, x22, #1                // validate letters
    mov     x4, x3
.v:
    ldrb    w9, [x3]
    cbz     w9, .apply
    cmp     w9, #'i'
    b.eq    .v_ok
    cmp     w9, #'v'
    b.eq    .v_ok
    cmp     w9, #'n'
    b.eq    .v_ok
    cmp     w9, #'c'
    b.eq    .v_ok
    cmp     w9, #'w'
    b.eq    .v_ok
    cmp     w9, #'x'
    b.eq    .v_ok
    b       .have_pat                  // unknown -> treat token as the pattern
.v_ok:
    add     x3, x3, #1
    b       .v
.apply:
    mov     x3, x4
.ap:
    ldrb    w9, [x3]
    cbz     w9, .apd
    cmp     w9, #'i'
    b.ne    .ap2
    ldr     x10, [x29, #LOC_FLAGS]
    orr     x10, x10, #1
    str     x10, [x29, #LOC_FLAGS]
.ap2:
    cmp     w9, #'v'
    b.ne    .ap3
    ldr     x10, [x29, #LOC_FLAGS]
    orr     x10, x10, #2
    str     x10, [x29, #LOC_FLAGS]
.ap3:
    cmp     w9, #'n'
    b.ne    .ap7
    ldr     x10, [x29, #LOC_FLAGS]
    orr     x10, x10, #4
    str     x10, [x29, #LOC_FLAGS]
.ap7:
    cmp     w9, #'c'
    b.ne    .ap8
    ldr     x10, [x29, #LOC_FLAGS]
    orr     x10, x10, #8
    str     x10, [x29, #LOC_FLAGS]
.ap8:
    cmp     w9, #'w'
    b.ne    .ap9
    ldr     x10, [x29, #LOC_FLAGS]
    orr     x10, x10, #16
    str     x10, [x29, #LOC_FLAGS]
.ap9:
    cmp     w9, #'x'
    b.ne    .ap10
    ldr     x10, [x29, #LOC_FLAGS]
    orr     x10, x10, #32
    str     x10, [x29, #LOC_FLAGS]
.ap10:
    add     x3, x3, #1
    b       .ap
.apd:
    add     x21, x21, #8
    sub     x20, x20, #1
    b       .opt
.ddash:
    ldrb    w9, [x22, #2]
    cbnz    w9, .have_pat
    add     x21, x21, #8
    sub     x20, x20, #1

.have_pat:
    cbz     x20, .usage
    ldr     x0, [x21]
    str     x0, [x29, #LOC_PAT]
    bl      uolt_strlen
    str     x0, [x29, #LOC_PATLEN]
    add     x21, x21, #8
    sub     x20, x20, #1

    cbnz    x20, .files
    str     xzr, [x29, #LOC_NAME]      // no operands: stdin, no name prefix
    mov     x0, #STDIN
    bl      grep_fd
    b       .fin
.files:
    cmp     x20, #1                    // prefix names only when >1 file
    cset    w23, gt
.floop:
    cbz     x20, .fin
    ldr     x22, [x21]
    mov     x0, x22
    mov     x1, #0
    mov     x2, #0
    bl      uolt_open
    cmp     x0, #0
    b.mi    .fopenerr
    mov     x24, x0                    // fd (preserved across grep_fd)
    cbz     x23, .fl_noname
    str     x22, [x29, #LOC_NAME]
    b       .fl_run
.fl_noname:
    str     xzr, [x29, #LOC_NAME]
.fl_run:
    mov     x0, x24
    bl      grep_fd
    mov     x0, x24
    bl      uolt_close
    b       .fnext
.fopenerr:
    mov     x9, #1
    str     x9, [x29, #LOC_ERR]
    adr     x0, err_pre
    bl      err_puts
    mov     x0, x22
    bl      err_puts
    adr     x0, err_suf
    bl      err_puts
.fnext:
    add     x21, x21, #8
    sub     x20, x20, #1
    b       .floop

.fin:
    ldr     x9, [x29, #LOC_ERR]
    cbnz    x9, .ex2
    ldr     x9, [x29, #LOC_MATCH]
    cbnz    x9, .ex0
    mov     x0, #1                     // no matches
    b       .ret
.ex0:
    mov     x0, #0
    b       .ret
.ex2:
    mov     x0, #2
.ret:
    mov     sp, x29
    ldp     x19, x20, [sp, #0]
    ldp     x21, x22, [sp, #16]
    ldp     x23, x30, [sp, #32]
    add     sp, sp, #160
    ret
.usage:
    adr     x0, err_usage
    bl      err_puts
    mov     x0, #2
    b       .ret

// grep_fd(x0 = fd): read the descriptor, split into lines, print matches. Saves
// x20/x21/x22.
grep_fd:
    sub     sp, sp, #48
    stp     x20, x21, [sp, #0]
    stp     x22, x30, [sp, #16]
    mov     x20, x0                    // fd
    mov     x21, #0                    // fill
    str     xzr, [x29, #LOC_LINENO]
    str     xzr, [x29, #LOC_COUNT]
.gf_read:
    mov     x2, #BUFSZ
    sub     x2, x2, x21
    cbz     x2, .gf_longline
    mov     x0, x20
    add     x1, x19, x21
    bl      uolt_read
    cmp     x0, #0
    b.eq    .gf_eof
    b.mi    .gf_readerr
    add     x21, x21, x0
    mov     x22, #0                    // start of the current line
.gf_scan:
    mov     x9, x22
.gf_find:
    cmp     x9, x21
    b.hs    .gf_compact
    ldrb    w10, [x19, x9]
    cmp     w10, #0x0a
    b.eq    .gf_line
    add     x9, x9, #1
    b       .gf_find
.gf_line:
    add     x0, x19, x22
    sub     x1, x9, x22
    add     x22, x9, #1
    bl      process_line
    b       .gf_scan
.gf_compact:
    sub     x11, x21, x22
    mov     x9, #0
.gf_cp:
    cmp     x9, x11
    b.hs    .gf_cpd
    add     x12, x19, x22
    ldrb    w13, [x12, x9]
    strb    w13, [x19, x9]
    add     x9, x9, #1
    b       .gf_cp
.gf_cpd:
    mov     x21, x11
    b       .gf_read
.gf_longline:
    mov     x0, x19
    mov     x1, x21
    bl      process_line
    mov     x21, #0
    b       .gf_read
.gf_eof:
    cbz     x21, .gf_done
    mov     x0, x19
    mov     x1, x21
    bl      process_line
.gf_done:
    ldr     x9, [x29, #LOC_FLAGS]
    tbz     x9, #3, .gfd_ret           // -c: print the match count
    ldr     x9, [x29, #LOC_NAME]
    cbz     x9, .gfd_nn
    mov     x0, x9
    bl      put_str
    mov     w0, #':'
    bl      put_char
.gfd_nn:
    ldr     x0, [x29, #LOC_COUNT]
    bl      put_uint
    mov     w0, #0x0a
    bl      put_char
.gfd_ret:
    ldp     x20, x21, [sp, #0]
    ldp     x22, x30, [sp, #16]
    add     sp, sp, #48
    ret
.gf_readerr:
    mov     x9, #1
    str     x9, [x29, #LOC_ERR]
    ldp     x20, x21, [sp, #0]
    ldp     x22, x30, [sp, #16]
    add     sp, sp, #48
    ret

// process_line(x0 = line ptr, x1 = line length): test the match (accounting for
// -v) and print if it matches. x24 = line ptr, x25 = len (saved).
process_line:
    sub     sp, sp, #32
    stp     x24, x25, [sp, #0]
    str     x30, [sp, #16]
    mov     x24, x0
    mov     x25, x1
    ldr     x9, [x29, #LOC_LINENO]
    add     x9, x9, #1
    str     x9, [x29, #LOC_LINENO]
    mov     x0, x24
    mov     x1, x25
    ldr     x2, [x29, #LOC_PAT]
    ldr     x3, [x29, #LOC_PATLEN]
    ldr     x4, [x29, #LOC_FLAGS]
    and     x4, x4, #1                 // -i
    bl      contains
    ldr     x9, [x29, #LOC_FLAGS]
    tbz     x9, #1, .pl_nov            // -v inverts
    eor     x0, x0, #1
.pl_nov:
    cbz     x0, .pl_done
    mov     x9, #1
    str     x9, [x29, #LOC_MATCH]
    ldr     x9, [x29, #LOC_FLAGS]
    tbz     x9, #3, .pl_print          // -c: count only
    ldr     x9, [x29, #LOC_COUNT]
    add     x9, x9, #1
    str     x9, [x29, #LOC_COUNT]
    b       .pl_done
.pl_print:
    ldr     x9, [x29, #LOC_NAME]       // optional "name:" prefix
    cbz     x9, .pl_noname
    mov     x0, x9
    bl      put_str
    mov     w0, #':'
    bl      put_char
.pl_noname:
    ldr     x9, [x29, #LOC_FLAGS]      // optional "lineno:" prefix (-n)
    tbz     x9, #2, .pl_noln
    ldr     x0, [x29, #LOC_LINENO]
    bl      put_uint
    mov     w0, #':'
    bl      put_char
.pl_noln:
    mov     x0, #STDOUT
    mov     x1, x24
    mov     x2, x25
    bl      uolt_write
    mov     w0, #0x0a
    bl      put_char
.pl_done:
    ldp     x24, x25, [sp, #0]
    ldr     x30, [sp, #16]
    add     sp, sp, #32
    ret

// contains(x0=line, x1=len, x2=pat, x3=patlen, x4=ci) -> x0 = 1 if the pattern
// occurs. Naive scan. State in x9-x14/x5, so is_word (x0 only) doesn't disturb it.
contains:
    sub     sp, sp, #16
    str     x30, [sp, #0]
    mov     x9, x0                     // line
    str     x1, [x29, #LOC_XLEN]       // original line length
    mov     x10, x2                    // pat
    mov     x11, x3                    // patlen
    mov     x12, x4                    // ci
    ldr     x15, [x29, #LOC_FLAGS]
    tbnz    x15, #5, .ct_exact         // -x: whole-line match
    cbz     x11, .ct_yes               // empty pattern matches
    sub     x13, x1, x11               // last possible start index
    cmp     x13, #0
    b.lt    .ct_no                     // line shorter than the pattern
    mov     x14, #0                    // i
.ct_out:
    cmp     x14, x13
    b.gt    .ct_no
    mov     x5, #0                     // j
.ct_in:
    cmp     x5, x11
    b.eq    .ct_matched
    add     x6, x9, x14
    ldrb    w6, [x6, x5]               // line[i+j]
    ldrb    w7, [x10, x5]              // pat[j]
    cbz     x12, .ct_cmp
    cmp     w6, #'A'
    b.lo    .ct_a2
    cmp     w6, #'Z'
    b.hi    .ct_a2
    add     w6, w6, #0x20
.ct_a2:
    cmp     w7, #'A'
    b.lo    .ct_cmp
    cmp     w7, #'Z'
    b.hi    .ct_cmp
    add     w7, w7, #0x20
.ct_cmp:
    cmp     w6, w7
    b.ne    .ct_next
    add     x5, x5, #1
    b       .ct_in
.ct_matched:
    ldr     x15, [x29, #LOC_FLAGS]
    tbz     x15, #4, .ct_yes           // -w: require word boundaries
    cbz     x14, .cw_left              // start of line
    sub     x6, x14, #1
    add     x6, x9, x6
    ldrb    w0, [x6]                   // line[i-1]
    bl      is_word
    cbnz    x0, .ct_next               // word char to the left
.cw_left:
    add     x6, x14, x11               // index just past the match
    ldr     x7, [x29, #LOC_XLEN]
    cmp     x6, x7
    b.hs    .ct_yes
    add     x7, x9, x6
    ldrb    w0, [x7]
    bl      is_word
    cbnz    x0, .ct_next
    b       .ct_yes
.ct_next:
    add     x14, x14, #1
    b       .ct_out
.ct_exact:
    ldr     x1, [x29, #LOC_XLEN]
    cmp     x1, x11                    // lengths differ -> no match
    b.ne    .ct_no
    mov     x14, #0
.cx_lp:
    cmp     x14, x11
    b.eq    .ct_yes
    ldrb    w6, [x9, x14]
    ldrb    w7, [x10, x14]
    cbz     x12, .cx_cmp
    cmp     w6, #'A'
    b.lo    .cx_a2
    cmp     w6, #'Z'
    b.hi    .cx_a2
    add     w6, w6, #0x20
.cx_a2:
    cmp     w7, #'A'
    b.lo    .cx_cmp
    cmp     w7, #'Z'
    b.hi    .cx_cmp
    add     w7, w7, #0x20
.cx_cmp:
    cmp     w6, w7
    b.ne    .ct_no
    add     x14, x14, #1
    b       .cx_lp
.ct_yes:
    mov     x0, #1
    ldr     x30, [sp, #0]
    add     sp, sp, #16
    ret
.ct_no:
    mov     x0, #0
    ldr     x30, [sp, #0]
    add     sp, sp, #16
    ret

// is_word(w0) -> x0 = 1 if w0 is [A-Za-z0-9_], else 0. Clobbers only x0.
is_word:
    cmp     w0, #'0'
    b.lo    .iw_no
    cmp     w0, #'9'
    b.ls    .iw_yes
    cmp     w0, #'A'
    b.lo    .iw_no
    cmp     w0, #'Z'
    b.ls    .iw_yes
    cmp     w0, #'a'
    b.lo    .iw_us
    cmp     w0, #'z'
    b.ls    .iw_yes
    b       .iw_no
.iw_us:
    cmp     w0, #'_'
    b.eq    .iw_yes
.iw_no:
    mov     x0, #0
    ret
.iw_yes:
    mov     x0, #1
    ret

// put_char(w0 = byte): write one byte to stdout.
put_char:
    strb    w0, [x29, #LOC_CH]
    mov     x0, #STDOUT
    add     x1, x29, #LOC_CH
    mov     x2, #1
    b       uolt_write

// put_uint(x0 = value): write the unsigned decimal to stdout.
put_uint:
    add     x9, x29, #LOC_NUM
    add     x9, x9, #20                // one-past
    cbnz    x0, .pu_go
    sub     x9, x9, #1
    mov     w10, #'0'
    strb    w10, [x9]
    b       .pu_emit
.pu_go:
    mov     x11, x0
    mov     x12, #10
.pu_lp:
    cbz     x11, .pu_emit
    udiv    x13, x11, x12
    msub    x14, x13, x12, x11
    add     w14, w14, #'0'
    sub     x9, x9, #1
    strb    w14, [x9]
    mov     x11, x13
    b       .pu_lp
.pu_emit:
    add     x10, x29, #LOC_NUM
    add     x10, x10, #20
    sub     x2, x10, x9
    mov     x1, x9
    mov     x0, #STDOUT
    b       uolt_write

// put_str(x0 = ASCIZ): write the string to stdout. Saves lr.
put_str:
    stp     x29, x30, [sp, #-16]!
    mov     x3, x0
    bl      uolt_strlen
    mov     x2, x0
    mov     x1, x3
    mov     x0, #STDOUT
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

err_usage: .asciz "uolt-grep: usage: grep [-ivncwx] pattern [file...]\n"
err_pre:   .asciz "uolt-grep: "
err_suf:   .asciz ": cannot open\n"
