// src/tail/arm64/tail.S - uolt-tail: the POSIX `tail` utility, aarch64.
//
// Writes the last N lines (default 10) of each file operand, or of stdin. With
// "-n +N" it starts at line N and copies to the end; -c switches to bytes. Only
// POSIX -n (and -c) are recognized; "--" ends options. Multi-operand output gets
// "==> name <==" headers. Mirrors the x86_64 body.
//
// Seekable input: lseek to end, read 64 KB blocks backwards counting newlines,
// seek to the Nth boundary, copy forward. Non-seekable (pipe): slurp into a
// growable mmap region (double, copy, munmap) then locate the last N lines/bytes.
// No heap (Principle IV); the region is released afterwards.
//
// Callee-saved: x19 = current argv entry; x20 = exit status; x21 = window buffer
//   base; x22 = operand string then fd; x25 = candidate operand count. Helpers keep
//   their own state in x23-x28 (saved per helper). Locals off x29.

#include "uolt.inc"

.set STDIN,    0
.set STDOUT,   1
.set STDERR,   2
.set O_RDONLY, 0
.set BUFSZ,       65536
.set SLURP_START, 0x100000
.set DEFLINES,   10
.set SEEK_SET,   0
.set SEEK_END,   2

.set LOC_REM,   48
.set LOC_HDR,   56
.set LOC_FIRST, 64
.set LOC_N,     72
.set LOC_PLUS,  80
.set LOC_CNT,   88
.set LOC_FB,    96
.set LOC_CS,    104
.set LOC_BYTES, 112
.set LOC_SCAP,  120
.set LOC_SNC,   128
.set LOC_SNB,   136
.set FRAME,     144

.text
.globl uolt_main
uolt_main:
    sub     sp, sp, #FRAME
    mov     x29, sp
    str     x30, [x29, #0]
    stp     x19, x20, [x29, #16]
    stp     x21, x22, [x29, #32]
    sub     sp, sp, #131072            // 2 * BUFSZ window buffer
    mov     x21, sp
    mov     x20, #0                    // exit status
    mov     x9, #DEFLINES
    str     x9, [x29, #LOC_N]
    str     xzr, [x29, #LOC_PLUS]
    str     xzr, [x29, #LOC_BYTES]
    add     x19, x1, #8                // &argv[1]
    sub     x25, x0, #1                // candidate operand count
.opt:
    cbz     x25, .opt_done
    ldr     x22, [x19]
    ldrb    w9, [x22]
    cmp     w9, #'-'
    b.ne    .opt_done
    ldrb    w9, [x22, #1]
    cbz     w9, .opt_done              // "-" operand (stdin)
    cmp     w9, #'-'
    b.ne    .chk_n
    ldrb    w9, [x22, #2]
    cbnz    w9, .chk_n
    add     x19, x19, #8               // "--": end of options
    sub     x25, x25, #1
    b       .opt_done
.chk_n:
    ldrb    w9, [x22, #1]
    cmp     w9, #'n'
    b.eq    .nc_num
    cmp     w9, #'c'
    b.ne    .opt_done
    mov     x9, #1
    str     x9, [x29, #LOC_BYTES]
.nc_num:
    ldrb    w9, [x22, #2]
    cbnz    w9, .n_joined
    add     x19, x19, #8               // "-n" number (next argument)
    sub     x25, x25, #1
    cbz     x25, .n_missing
    ldr     x0, [x19]
    bl      .set_count
    add     x19, x19, #8
    sub     x25, x25, #1
    b       .opt
.n_joined:
    add     x0, x22, #2                // "-nnumber"
    bl      .set_count
    add     x19, x19, #8
    sub     x25, x25, #1
    b       .opt

// .set_count(x0 = number string, possibly "+"-prefixed): records N and plus.
.set_count:
    stp     x29, x30, [sp, #-16]!
    str     xzr, [x29, #LOC_PLUS]
    ldrb    w9, [x0]
    cmp     w9, #'+'
    b.ne    .sc_go
    mov     x9, #1
    str     x9, [x29, #LOC_PLUS]
    add     x0, x0, #1
.sc_go:
    bl      parse_uint
    str     x0, [x29, #LOC_N]
    ldp     x29, x30, [sp], #16
    ret

.n_missing:
    mov     x20, #1
    adr     x0, err_narg
    bl      err_puts
    b       .finish

.opt_done:
    str     x25, [x29, #LOC_REM]
    cbnz    x25, .have_ops
    mov     x22, #STDIN                // no operand -> stdin, no header
    bl      .run_one
    b       .finish
.have_ops:
    str     xzr, [x29, #LOC_HDR]
    cmp     x25, #1
    b.ls    .ho1
    mov     x9, #1
    str     x9, [x29, #LOC_HDR]
.ho1:
    mov     x9, #1
    str     x9, [x29, #LOC_FIRST]
.ploop:
    ldr     x9, [x29, #LOC_REM]
    cbz     x9, .finish
    ldr     x22, [x19]
    ldrb    w9, [x22]
    cmp     w9, #'-'
    b.ne    .pf_open
    ldrb    w9, [x22, #1]
    cbnz    w9, .pf_open
    // stdin operand ("-")
    ldr     x9, [x29, #LOC_HDR]
    cbz     x9, .po_stdin
    adr     x1, stdin_name
    bl      print_header
.po_stdin:
    mov     x22, #STDIN
    bl      .run_one
    b       .pnext
.pf_open:
    mov     x0, x22
    mov     x1, #O_RDONLY
    mov     x2, #0
    bl      uolt_open
    cmp     x0, #0
    b.mi    .pf_err
    mov     x22, x0                    // fd
    ldr     x9, [x29, #LOC_HDR]
    cbz     x9, .po_run
    ldr     x1, [x19]                  // header name = filename
    bl      print_header
.po_run:
    bl      .run_one
    mov     x0, x22
    bl      uolt_close
    b       .pnext
.pf_err:
    mov     x20, #1
    adr     x0, err_pre
    bl      err_puts
    ldr     x0, [x19]
    bl      err_puts
    adr     x0, err_suf
    bl      err_puts
.pnext:
    add     x19, x19, #8
    ldr     x9, [x29, #LOC_REM]
    sub     x9, x9, #1
    str     x9, [x29, #LOC_REM]
    b       .ploop

// .run_one: process descriptor x22 per the parsed N / plus / bytes flags.
.run_one:
    stp     x29, x30, [sp, #-16]!
    mov     x0, x22
    ldr     x1, [x29, #LOC_N]
    ldr     x9, [x29, #LOC_BYTES]
    cbnz    x9, .ro_bytes
    ldr     x9, [x29, #LOC_PLUS]
    cbnz    x9, .ro_fwd_line
    bl      last_lines
    b       .ro_ret
.ro_fwd_line:
    bl      forward_from_line
    b       .ro_ret
.ro_bytes:
    ldr     x9, [x29, #LOC_PLUS]
    cbnz    x9, .ro_fwd_byte
    bl      last_bytes
    b       .ro_ret
.ro_fwd_byte:
    bl      forward_from_byte
.ro_ret:
    ldp     x29, x30, [sp], #16
    ret

.finish:
    mov     x0, x20
    mov     sp, x29
    ldr     x30, [x29, #0]
    ldp     x19, x20, [x29, #16]
    ldp     x21, x22, [x29, #32]
    add     sp, sp, #FRAME
    ret

// ------------------------------------------------------------------ helpers

// last_lines(x0 = fd, x1 = N): print the last N lines. Seeks on a regular file;
// falls back to the pipe path when not seekable. x23 = fd, x24 = N, x25 = chunkbase.
last_lines:
    sub     sp, sp, #48
    stp     x23, x24, [sp, #0]
    stp     x25, x30, [sp, #16]
    mov     x23, x0
    mov     x24, x1
    cbz     x24, .ll_done              // -n 0
    mov     x0, x23                    // end = lseek(fd, 0, SEEK_END)
    mov     x1, #0
    mov     x2, #SEEK_END
    bl      uolt_lseek
    cmp     x0, #0
    b.mi    .ll_pipe                   // not seekable
    b.eq    .ll_done                   // empty file
    mov     x25, x0
    str     xzr, [x29, #LOC_CNT]
    mov     x9, #1
    str     x9, [x29, #LOC_FB]
.bs_chunk:
    cbz     x25, .bs_whole
    mov     x9, #BUFSZ                 // csize = min(BUFSZ, chunkbase)
    cmp     x25, x9
    b.hs    .bs_cs
    mov     x9, x25
.bs_cs:
    sub     x25, x25, x9
    str     x9, [x29, #LOC_CS]
    mov     x0, x23                    // lseek(fd, chunkbase, SEEK_SET)
    mov     x1, x25
    mov     x2, #SEEK_SET
    bl      uolt_lseek
    mov     x0, x23                    // read_exact(fd, buf, csize)
    mov     x1, x21
    ldr     x2, [x29, #LOC_CS]
    bl      read_exact
    mov     x2, x0                     // i = bytes available
.bs_scan:
    cbz     x2, .bs_chunk
    sub     x2, x2, #1
    ldr     x9, [x29, #LOC_FB]
    cbz     x9, .bs_notfb
    str     xzr, [x29, #LOC_FB]
    ldrb    w9, [x21, x2]              // skip one trailing newline
    cmp     w9, #0x0a
    b.eq    .bs_scan
.bs_notfb:
    ldrb    w9, [x21, x2]
    cmp     w9, #0x0a
    b.ne    .bs_scan
    ldr     x9, [x29, #LOC_CNT]
    add     x9, x9, #1
    str     x9, [x29, #LOC_CNT]
    cmp     x9, x24                    // found N newlines?
    b.ne    .bs_scan
    add     x0, x25, x2                // start = chunkbase + i + 1
    add     x0, x0, #1
    b       .bs_emit
.bs_whole:
    mov     x0, #0
.bs_emit:
    mov     x1, x0
    mov     x0, x23                    // lseek(fd, start, SEEK_SET)
    mov     x2, #SEEK_SET
    bl      uolt_lseek
    mov     x0, x23
    bl      copy_to_eof
.ll_done:
    ldp     x23, x24, [sp, #0]
    ldp     x25, x30, [sp, #16]
    add     sp, sp, #48
    ret
.ll_pipe:
    mov     x0, x23
    mov     x1, x24
    bl      last_lines_pipe
    b       .ll_done

// last_lines_pipe(x0 = fd, x1 = N): slurp the stream, scan backwards for the Nth-
// from-last newline. x23 = N, x24 = base, x25 = len.
last_lines_pipe:
    sub     sp, sp, #48
    stp     x23, x24, [sp, #0]
    stp     x25, x30, [sp, #16]
    mov     x23, x1
    cbz     x23, .lp_fin               // -n 0
    bl      slurp                      // x0 = base, x1 = len
    mov     x24, x0
    mov     x25, x1
    cbz     x25, .lp_free
    mov     x9, x25                    // e; ignore one trailing newline
    sub     x10, x25, #1
    ldrb    w11, [x24, x10]
    cmp     w11, #0x0a
    b.ne    .lp_e_ok
    sub     x9, x9, #1
.lp_e_ok:
    mov     x10, #0                    // count
    mov     x11, x9                    // i = e
.lp_scan:
    cbz     x11, .lp_whole
    sub     x11, x11, #1
    ldrb    w12, [x24, x11]
    cmp     w12, #0x0a
    b.ne    .lp_scan
    add     x10, x10, #1
    cmp     x10, x23
    b.ne    .lp_scan
    add     x11, x11, #1               // start = i + 1
    b       .lp_emit
.lp_whole:
    mov     x11, #0
.lp_emit:
    add     x1, x24, x11
    sub     x2, x25, x11               // length = len - start
    bl      emit
.lp_free:
    ldr     x9, [x29, #LOC_SCAP]
    cbz     x9, .lp_fin
    mov     x0, x24
    ldr     x1, [x29, #LOC_SCAP]
    bl      uolt_munmap
.lp_fin:
    ldp     x23, x24, [sp, #0]
    ldp     x25, x30, [sp, #16]
    add     sp, sp, #48
    ret

// last_bytes(x0 = fd, x1 = N): print the last N bytes. x23 = fd, x24 = N.
last_bytes:
    sub     sp, sp, #32
    stp     x23, x24, [sp, #0]
    str     x30, [sp, #16]
    mov     x23, x0
    mov     x24, x1
    cbz     x24, .lb_done
    mov     x0, x23
    mov     x1, #0
    mov     x2, #SEEK_END
    bl      uolt_lseek
    cmp     x0, #0
    b.mi    .lb_pipe
    sub     x0, x0, x24                // start = end - N (clamp to 0)
    cmp     x0, #0
    b.ge    .lb_seek
    mov     x0, #0
.lb_seek:
    mov     x1, x0
    mov     x0, x23
    mov     x2, #SEEK_SET
    bl      uolt_lseek
    mov     x0, x23
    bl      copy_to_eof
.lb_done:
    ldp     x23, x24, [sp, #0]
    ldr     x30, [sp, #16]
    add     sp, sp, #32
    ret
.lb_pipe:
    mov     x0, x23
    mov     x1, x24
    bl      last_bytes_pipe
    b       .lb_done

// last_bytes_pipe(x0 = fd, x1 = N): slurp, emit the final N bytes. x23=N,x24=base,x25=len.
last_bytes_pipe:
    sub     sp, sp, #48
    stp     x23, x24, [sp, #0]
    stp     x25, x30, [sp, #16]
    mov     x23, x1
    bl      slurp
    mov     x24, x0
    mov     x25, x1
    cbz     x25, .lbp_free
    mov     x0, x25                    // start = max(0, len - N)
    sub     x0, x0, x23
    cmp     x0, #0
    b.ge    .lbp_emit
    mov     x0, #0
.lbp_emit:
    add     x1, x24, x0
    sub     x2, x25, x0
    bl      emit
.lbp_free:
    ldr     x9, [x29, #LOC_SCAP]
    cbz     x9, .lbp_fin
    mov     x0, x24
    ldr     x1, [x29, #LOC_SCAP]
    bl      uolt_munmap
.lbp_fin:
    ldp     x23, x24, [sp, #0]
    ldp     x25, x30, [sp, #16]
    add     sp, sp, #48
    ret

// slurp(x0 = fd) -> x0 = base, x1 = len. Reads the whole descriptor into a
// growable mmap region. Capacity left in LOC_SCAP (0 on failure). Sets x20 = 1 on
// error. x23 = fd, x24 = base, x25 = len.
slurp:
    sub     sp, sp, #48
    stp     x23, x24, [sp, #0]
    stp     x25, x30, [sp, #16]
    mov     x23, x0
    mov     x0, #SLURP_START
    bl      uolt_mmap_anon
    cmp     x0, #0
    b.mi    .sl_err
    mov     x24, x0
    mov     x9, #SLURP_START
    str     x9, [x29, #LOC_SCAP]
    mov     x25, #0
.sl_read:
    ldr     x9, [x29, #LOC_SCAP]
    cmp     x25, x9
    b.lo    .sl_space
    ldr     x9, [x29, #LOC_SCAP]       // grow: newcap = cap * 2
    add     x9, x9, x9
    str     x9, [x29, #LOC_SNC]
    mov     x0, x9
    bl      uolt_mmap_anon
    cmp     x0, #0
    b.mi    .sl_err2
    str     x0, [x29, #LOC_SNB]
    mov     x10, #0
.sl_cp:
    cmp     x10, x25
    b.hs    .sl_cpd
    ldrb    w11, [x24, x10]
    strb    w11, [x0, x10]
    add     x10, x10, #1
    b       .sl_cp
.sl_cpd:
    mov     x0, x24
    ldr     x1, [x29, #LOC_SCAP]
    bl      uolt_munmap
    ldr     x24, [x29, #LOC_SNB]
    ldr     x9, [x29, #LOC_SNC]
    str     x9, [x29, #LOC_SCAP]
.sl_space:
    ldr     x2, [x29, #LOC_SCAP]
    sub     x2, x2, x25
    mov     x0, x23
    add     x1, x24, x25
    bl      uolt_read
    cmp     x0, #0
    b.le    .sl_done
    add     x25, x25, x0
    b       .sl_read
.sl_done:
    mov     x0, x24
    mov     x1, x25
    ldp     x23, x24, [sp, #0]
    ldp     x25, x30, [sp, #16]
    add     sp, sp, #48
    ret
.sl_err2:
    mov     x0, x24                    // free the partial region
    ldr     x1, [x29, #LOC_SCAP]
    bl      uolt_munmap
.sl_err:
    mov     x20, #1
    mov     x0, #0
    mov     x1, #0
    str     xzr, [x29, #LOC_SCAP]
    ldp     x23, x24, [sp, #0]
    ldp     x25, x30, [sp, #16]
    add     sp, sp, #48
    ret

// forward_from_byte(x0 = fd, x1 = startbyte): copy from byte startbyte (1-based)
// to EOF. x23 = fd, x24 = bytes to skip.
forward_from_byte:
    sub     sp, sp, #32
    stp     x23, x24, [sp, #0]
    str     x30, [sp, #16]
    mov     x23, x0
    sub     x24, x1, #1
    cmp     x24, #0
    b.le    .fb_all
.fb_read:
    mov     x0, x23
    mov     x1, x21
    mov     x2, #BUFSZ
    bl      uolt_read
    cmp     x0, #0
    b.eq    .fb_done
    b.mi    .fb_err
    cmp     x24, x0
    b.hs    .fb_skipblock
    add     x1, x21, x24               // emit the rest of this block
    sub     x2, x0, x24
    bl      emit
    mov     x0, x23
    bl      copy_to_eof
    b       .fb_done
.fb_skipblock:
    sub     x24, x24, x0
    b       .fb_read
.fb_all:
    mov     x0, x23
    bl      copy_to_eof
.fb_done:
    ldp     x23, x24, [sp, #0]
    ldr     x30, [sp, #16]
    add     sp, sp, #32
    ret
.fb_err:
    mov     x20, #1
    b       .fb_done

// forward_from_line(x0 = fd, x1 = startline): copy from line startline (1-based)
// to EOF. Streams (works on files and pipes). x23 = fd, x24 = lines to skip,
// x25 = block length.
forward_from_line:
    sub     sp, sp, #48
    stp     x23, x24, [sp, #0]
    stp     x25, x30, [sp, #16]
    mov     x23, x0
    sub     x24, x1, #1
    cmp     x24, #0
    b.le    .ff_all
.ff_read:
    mov     x0, x23
    mov     x1, x21
    mov     x2, #BUFSZ
    bl      uolt_read
    cmp     x0, #0
    b.eq    .ff_done
    b.mi    .ff_err
    mov     x25, x0                    // block length
    mov     x9, #0                     // i
.ff_scan:
    cmp     x9, x25
    b.hs    .ff_read
    ldrb    w10, [x21, x9]
    cmp     w10, #0x0a
    b.ne    .ff_next
    sub     x24, x24, #1
    cbz     x24, .ff_rest
.ff_next:
    add     x9, x9, #1
    b       .ff_scan
.ff_rest:
    add     x9, x9, #1                 // just after the newline
    add     x1, x21, x9
    sub     x2, x25, x9
    bl      emit
    mov     x0, x23
    bl      copy_to_eof
    b       .ff_done
.ff_all:
    mov     x0, x23
    bl      copy_to_eof
    b       .ff_done
.ff_err:
    mov     x20, #1
.ff_done:
    ldp     x23, x24, [sp, #0]
    ldp     x25, x30, [sp, #16]
    add     sp, sp, #48
    ret

// copy_to_eof(x0 = fd): copy from the current file position to EOF. x26 = fd,
// x27 = drain ptr, x28 = remaining. Sets x20 on error.
copy_to_eof:
    stp     x26, x27, [sp, #-32]!
    stp     x28, x30, [sp, #16]
    mov     x26, x0
.ce_read:
    mov     x0, x26
    mov     x1, x21
    mov     x2, #BUFSZ
    bl      uolt_read
    cmp     x0, #0
    b.eq    .ce_done
    b.mi    .ce_err
    mov     x27, x21
    mov     x28, x0
.ce_w:
    mov     x0, #STDOUT
    mov     x1, x27
    mov     x2, x28
    bl      uolt_write
    cmp     x0, #0
    b.mi    .ce_err
    add     x27, x27, x0
    subs    x28, x28, x0
    b.ne    .ce_w
    b       .ce_read
.ce_err:
    mov     x20, #1
.ce_done:
    ldp     x26, x27, [sp, #0]
    ldp     x28, x30, [sp, #16]
    add     sp, sp, #32
    ret

// read_exact(x0 = fd, x1 = buf, x2 = count) -> x0 = bytes read. x26 = fd,
// x27 = buf cursor, x28 = remaining.
read_exact:
    sub     sp, sp, #48
    stp     x26, x27, [sp, #0]
    stp     x28, x30, [sp, #16]
    mov     x26, x0
    mov     x27, x1
    mov     x28, x2
    str     x2, [sp, #32]              // original count
.re_l:
    cbz     x28, .re_done
    mov     x0, x26
    mov     x1, x27
    mov     x2, x28
    bl      uolt_read
    cmp     x0, #0
    b.le    .re_done
    add     x27, x27, x0
    sub     x28, x28, x0
    b       .re_l
.re_done:
    ldr     x9, [sp, #32]
    sub     x0, x9, x28
    ldp     x26, x27, [sp, #0]
    ldp     x28, x30, [sp, #16]
    add     sp, sp, #48
    ret

// emit(x1 = buf, x2 = len): drain to stdout, tolerating short writes. x27 = ptr,
// x28 = remaining. Sets x20 on error.
emit:
    stp     x27, x28, [sp, #-32]!
    str     x30, [sp, #16]
    mov     x27, x1
    mov     x28, x2
.emit_l:
    cbz     x28, .emit_done
    mov     x0, #STDOUT
    mov     x1, x27
    mov     x2, x28
    bl      uolt_write
    cmp     x0, #0
    b.mi    .emit_err
    add     x27, x27, x0
    sub     x28, x28, x0
    b       .emit_l
.emit_err:
    mov     x20, #1
.emit_done:
    ldr     x30, [sp, #16]
    ldp     x27, x28, [sp], #32
    ret

// print_header(x1 = name): write "==> name <==\n", preceded by a blank line except
// the first time. x23 = name.
print_header:
    stp     x23, x30, [sp, #-16]!
    mov     x23, x1
    ldr     x9, [x29, #LOC_FIRST]
    cbnz    x9, .ph_first
    mov     x0, #STDOUT
    adr     x1, nl_char
    mov     x2, #1
    bl      uolt_write
.ph_first:
    str     xzr, [x29, #LOC_FIRST]
    mov     x0, #STDOUT
    adr     x1, hdr_pre
    mov     x2, #4
    bl      uolt_write
    mov     x0, x23
    bl      uolt_strlen
    mov     x2, x0
    mov     x1, x23
    mov     x0, #STDOUT
    bl      uolt_write
    mov     x0, #STDOUT
    adr     x1, hdr_suf
    mov     x2, #5
    bl      uolt_write
    ldp     x23, x30, [sp], #16
    ret

// parse_uint(x0 = ASCIZ digits) -> x0. Stops at the first non-digit. Preserves
// x25 (the option-loop count).
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

hdr_pre:    .ascii  "==> "
hdr_suf:    .ascii  " <==\n"
nl_char:    .byte   0x0a
stdin_name: .asciz  "standard input"
err_pre:    .asciz  "uolt-tail: "
err_suf:    .asciz  ": cannot open\n"
err_narg:   .asciz  "uolt-tail: option requires an argument -- n\n"
