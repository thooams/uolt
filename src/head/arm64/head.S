// src/head/arm64/head.S - uolt-head: the POSIX `head` utility (aarch64).
//
// Writes the first N lines (default 10) of each operand, or stdin ("-"/none).
// With >1 operand, each is preceded by "==> name <==" and separated by a blank
// line. Options: -n (lines), -c (bytes), "--". Streams through one 64 KB stack
// buffer (no heap, Principle IV). A file that cannot open -> stderr diagnostic,
// exit 1, remaining operands still processed. Mirrors the x86_64 body.
//
// Callee-saved roles: x19 = line/byte count N, x20 = buffer base, x21 = exit
//   status, x22 = current operand / fd, x23 = &argv walk. Locals off x29.

#include "uolt.inc"

.set STDIN,    0
.set STDOUT,   1
.set STDERR,   2
.set O_RDONLY, 0
.set BUFSZ,    65536
.set DEFLINES, 10

.set LOC_REM,   48
.set LOC_HDR,   56
.set LOC_FIRST, 64
.set LOC_BYTES, 72

.text
.globl uolt_main
uolt_main:
    sub     sp, sp, #128
    mov     x29, sp
    stp     x19, x20, [sp, #0]
    stp     x21, x22, [sp, #16]
    stp     x23, x30, [sp, #32]
    sub     sp, sp, #BUFSZ
    mov     x20, sp                     // buffer base
    mov     x21, #0                     // exit status 0
    str     xzr, [x29, #LOC_BYTES]

    // --- Option parsing: N in x19, x23 -> first operand, count in x9. ---
    mov     x19, #DEFLINES
    add     x23, x1, #8                 // &argv[1]
    sub     x9, x0, #1                  // candidate operand count
.Lopt:
    cbz     x9, .Lopt_done
    ldr     x22, [x23]
    ldrb    w10, [x22]
    cmp     w10, #'-'
    b.ne    .Lopt_done
    ldrb    w10, [x22, #1]
    cbz     w10, .Lopt_done             // "-" is the stdin operand
    cmp     w10, #'-'
    b.ne    .Lchk_n
    ldrb    w10, [x22, #2]
    cbnz    w10, .Lchk_n                // "--foo" -> operand
    add     x23, x23, #8                // "--": end of options
    sub     x9, x9, #1
    b       .Lopt_done
.Lchk_n:
    ldrb    w10, [x22, #1]
    cmp     w10, #'n'
    b.eq    .Lnc_num
    cmp     w10, #'c'
    b.ne    .Lopt_done                  // unknown option -> operands
    mov     x10, #1
    str     x10, [x29, #LOC_BYTES]
.Lnc_num:
    ldrb    w10, [x22, #2]
    cbnz    w10, .Ln_joined
    add     x23, x23, #8                // "-n" with number in the next arg
    sub     x9, x9, #1
    cbz     x9, .Ln_missing
    ldr     x0, [x23]
    bl      parse_uint                  // preserves x9
    mov     x19, x0
    add     x23, x23, #8
    sub     x9, x9, #1
    b       .Lopt
.Ln_joined:
    add     x0, x22, #2                 // "-nNUMBER"
    bl      parse_uint
    mov     x19, x0
    add     x23, x23, #8
    sub     x9, x9, #1
    b       .Lopt
.Ln_missing:
    mov     x21, #1
    adr     x0, err_narg
    bl      err_puts
    b       .Lfinish
.Lopt_done:
    str     x9, [x29, #LOC_REM]
    cbnz    x9, .Lhave_ops
    mov     x22, #STDIN                 // no operands -> stdin, no header
    mov     x0, x19
    bl      head_run
    b       .Lfinish
.Lhave_ops:
    str     xzr, [x29, #LOC_HDR]        // headers only when >1 operand
    cmp     x9, #1
    b.ls    1f
    mov     x10, #1
    str     x10, [x29, #LOC_HDR]
1:
    mov     x10, #1
    str     x10, [x29, #LOC_FIRST]
.Lploop:
    ldr     x9, [x29, #LOC_REM]
    cbz     x9, .Lfinish
    ldr     x22, [x23]
    ldrb    w10, [x22]
    cmp     w10, #'-'
    b.ne    .Lpf_open
    ldrb    w10, [x22, #1]
    cbnz    w10, .Lpf_open
    ldr     x10, [x29, #LOC_HDR]        // stdin operand ("-")
    cbz     x10, 2f
    adr     x1, stdin_name
    bl      print_header
2:
    mov     x22, #STDIN
    mov     x0, x19
    bl      head_run
    b       .Lpnext
.Lpf_open:
    mov     x0, x22
    mov     x1, #O_RDONLY
    mov     x2, #0
    bl      uolt_open
    cmp     x0, #0
    b.mi    .Lpf_err
    mov     x22, x0                     // fd
    ldr     x10, [x29, #LOC_HDR]
    cbz     x10, 3f
    ldr     x1, [x23]                   // header name = filename
    bl      print_header
3:
    mov     x0, x19                     // line/byte count
    bl      head_run
    mov     x0, x22
    bl      uolt_close
    b       .Lpnext
.Lpf_err:
    mov     x21, #1                     // no header for a file that never opened
    adr     x0, err_pre
    bl      err_puts
    ldr     x0, [x23]
    bl      err_puts
    adr     x0, err_suf
    bl      err_puts
.Lpnext:
    add     x23, x23, #8
    ldr     x9, [x29, #LOC_REM]
    sub     x9, x9, #1
    str     x9, [x29, #LOC_REM]
    b       .Lploop
.Lfinish:
    mov     x0, x21
    add     sp, sp, #BUFSZ
    ldp     x19, x20, [sp, #0]
    ldp     x21, x22, [sp, #16]
    ldp     x23, x30, [sp, #32]
    add     sp, sp, #128
    ret

// head_run(x0 = N, x22 = fd): dispatch to line or byte copy per -c.
head_run:
    ldr     x9, [x29, #LOC_BYTES]
    cbz     x9, head_fd
    // fall through to head_bytes

// head_bytes(x0 = N, x22 = fd): copy the first N bytes to stdout.
head_bytes:
    stp     x29, x30, [sp, #-16]!
    mov     x11, x0                     // remaining bytes
1:
    cbz     x11, 3f
    mov     x0, x22
    mov     x1, x20
    mov     x2, #BUFSZ
    cmp     x2, x11
    b.ls    2f
    mov     x2, x11                     // never read more than remaining
2:
    bl      uolt_read
    cmp     x0, #0
    b.eq    3f
    b.mi    .Lhb_err
    sub     x11, x11, x0
    mov     x9, x0                      // drain the block
    mov     x10, x20
4:
    mov     x0, #STDOUT
    mov     x1, x10
    mov     x2, x9
    bl      uolt_write
    cmp     x0, #0
    b.mi    .Lhb_err
    add     x10, x10, x0
    subs    x9, x9, x0
    b.ne    4b
    b       1b
.Lhb_err:
    mov     x21, #1
3:
    ldp     x29, x30, [sp], #16
    ret

// head_fd(x0 = N, x22 = fd): copy the first N lines to stdout. x11 = remaining
// lines survives the read/write calls (kernel-preserved).
head_fd:
    stp     x29, x30, [sp, #-16]!
    mov     x11, x0                     // remaining lines
    cbz     x11, 9f
1:
    mov     x0, x22
    mov     x1, x20
    mov     x2, #BUFSZ
    bl      uolt_read
    cmp     x0, #0
    b.eq    9f
    b.mi    8f
    mov     x9, x20                     // cursor
    add     x10, x20, x0                // end
    mov     x12, x0                     // block length (for whole-block emit)
2:
    cmp     x9, x10
    b.eq    .Lwhole
    ldrb    w13, [x9]
    cmp     w13, #0x0a
    b.ne    3f
    add     x9, x9, #1                  // include the newline
    subs    x11, x11, #1
    b.eq    .Lcut
    b       2b
3:
    add     x9, x9, #1
    b       2b
.Lwhole:
    mov     x1, x20
    mov     x2, x12
    bl      emit
    b       1b
.Lcut:
    mov     x1, x20
    sub     x2, x9, x20                 // bytes up to & incl the Nth newline
    bl      emit
    b       9f
8:
    mov     x21, #1
9:
    ldp     x29, x30, [sp], #16
    ret

// emit(x1 = buf, x2 = len): drain to stdout tolerating short writes. Sets x21 on
// error. Uses x9/x10 (safe: head_fd re-scans after a whole-block emit).
emit:
    stp     x29, x30, [sp, #-16]!
    mov     x9, x1
    mov     x10, x2
1:
    cbz     x10, 2f
    mov     x0, #STDOUT
    mov     x1, x9
    mov     x2, x10
    bl      uolt_write
    cmp     x0, #0
    b.mi    3f
    add     x9, x9, x0
    sub     x10, x10, x0
    b       1b
3:
    mov     x21, #1
2:
    ldp     x29, x30, [sp], #16
    ret

// print_header(x1 = name): write "==> name <==\n" with a leading blank line
// except the first time. Preserves x22 (the caller's fd).
print_header:
    stp     x29, x30, [sp, #-16]!
    mov     x3, x1                      // name ptr (survives the calls)
    ldr     x9, [x29, #LOC_FIRST]
    cbnz    x9, 1f
    mov     x0, #STDOUT                 // blank-line separator
    adr     x1, nl_char
    mov     x2, #1
    bl      uolt_write
1:
    str     xzr, [x29, #LOC_FIRST]
    mov     x0, #STDOUT                 // "==> "
    adr     x1, hdr_pre
    mov     x2, #4
    bl      uolt_write
    mov     x0, x3                      // the name
    bl      uolt_strlen
    mov     x2, x0
    mov     x1, x3
    mov     x0, #STDOUT
    bl      uolt_write
    mov     x0, #STDOUT                 // " <==\n"
    adr     x1, hdr_suf
    mov     x2, #5
    bl      uolt_write
    ldp     x29, x30, [sp], #16
    ret

// parse_uint(x0 = ASCIZ) -> x0 = value; stops at the first non-digit. Uses only
// x0/x1/x2, so the caller's count in x9 survives.
parse_uint:
    mov     x1, x0
    mov     x0, #0
1:
    ldrb    w2, [x1]
    sub     w2, w2, #'0'
    cmp     w2, #9
    b.hi    2f
    add     x0, x0, x0, lsl #2          // x0 *= 5
    add     x0, x0, x0                  // x0 *= 2  => *10
    add     x0, x0, w2, uxtw
    add     x1, x1, #1
    b       1b
2:
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

hdr_pre:    .ascii  "==> "
hdr_suf:    .ascii  " <==\n"
nl_char:    .byte   0x0a
stdin_name: .asciz  "standard input"
err_pre:    .asciz  "uolt-head: "
err_suf:    .asciz  ": cannot open\n"
err_narg:   .asciz  "uolt-head: option requires an argument -- n\n"
