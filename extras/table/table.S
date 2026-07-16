// extras/table/table.S - uolt-table: render whitespace-columned stdin as a
// Unicode box-drawing table.
//
// uolt-table reads standard input, splits each line into fields on runs of
// blanks (space / tab), and prints the fields aligned into a grid drawn with
// Unicode box-drawing characters, e.g.
//
//     ls -l | uolt-table
//     ┌────────────┬───┬───────┬───────┐
//     │ -rw-r--r-- │ 1 │ thomas │ 1024  │
//     └────────────┴───┴───────┴───────┘
//
// This is NOT a POSIX tool: it belongs to the UOLT *extras* collection, a
// clearly separated set of non-core convenience utilities. It still obeys every
// other UOLT principle: pure x86_64 assembly, direct syscalls only, no libc, no
// heap (its buffers are explicit, failure-checked mmap regions), size-targeted,
// tested and benchmarked. Only Principle VIII (POSIX-only) is intentionally
// relaxed for the extras collection; see the constitution's Extras section.
//
// Design (no heap; unbounded input in constant working memory beyond the input):
//   * The whole of stdin is slurped into a GROWABLE anonymous mmap region
//     (double, copy, munmap the old) so any input size is handled without a
//     fixed buffer that would silently truncate (Principle IV allows this).
//   * A first pass over the buffer computes the column count and each column's
//     display width; a second pass re-scans the same buffer and emits the table.
//     No per-row or per-field allocation: the field boundaries are recomputed in
//     the second pass, so the only extra memory is a fixed column-width array
//     and a fixed output buffer.
//   * "Display width" counts UTF-8 code points (bytes whose top bits are not
//     10xxxxxx), so accented Latin text (é = 2 bytes, 1 column) aligns. Wide
//     (CJK) and combining code points are counted as one column each - a
//     documented limitation, not data loss.
//
// Called as uolt_main(argc in rdi, argv in rsi) by the per-OS entry shim.
// Standard input only (no file operands). The single option is -H: treat the
// first rendered row as a header and draw a separator rule (├───┼───┤) between
// it and the rest of the rows.
//
// Stack locals (rbp-relative), all below -40 so they never overlap the five
// callee-saved registers the prologue pushes into [rbp-8..-40]:
//   [-48]=input capacity  [-56]=input length (n)  [-64]=input end ptr
//   [-72]=column count     [-80]=output-buffer fill
//   [-88]=grow new-cap scratch  [-96]=grow new-base scratch
//   [-104]=current line end ptr  [-112]=field cursor ptr
//   [-120]=field start ptr  [-128]=field end ptr
//   [-136]=-H header flag  [-144]=header separator already drawn
//   [-152..-168]=hline's three glyph pointers (left/mid/right)

#include "uolt.inc"

.set STDIN,  0
.set STDOUT, 1
.set STDERR, 2

.set ICAP_START, 0x10000        // initial input buffer: 64 KiB (grows on demand)
.set OBUF_CAP,   0x10000        // output buffer: 64 KiB (flushed when full)
.set COLMAX,     1024           // max columns; beyond this we error out
.set COLW_BYTES, COLMAX * 8     // column-width array size (one qword per column)

.set LOC_ICAP,  -48
.set LOC_N,     -56
.set LOC_END,   -64
.set LOC_NCOLS, -72
.set LOC_OLEN,  -80
.set LOC_NC,    -88
.set LOC_NB,    -96
.set LOC_LEND,  -104
.set LOC_P,     -112
.set LOC_FS,    -120
.set LOC_FE,    -128
.set LOC_HEADER,  -136
.set LOC_SEPDONE, -144
.set LOC_GL,      -152
.set LOC_GM,      -160
.set LOC_GR,      -168

.text
.globl uolt_main
uolt_main:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 176
    cld

    // -H: draw a separator after the first row (treat it as a header). Parse
    // argv now, before mmap clobbers rdi/rsi. rax/rcx/r8/r9 are scratch here.
    mov     qword ptr [rbp + LOC_HEADER], 0
    mov     rcx, rdi                    // argc
    mov     r8, rsi                     // argv
    mov     rax, 1
.arg_l:
    cmp     rax, rcx
    jae     .arg_done
    mov     r9, [r8 + rax*8]            // argv[i]
    cmp     byte ptr [r9], '-'
    jne     .arg_next
    cmp     byte ptr [r9 + 1], 'H'
    jne     .arg_next
    cmp     byte ptr [r9 + 2], 0
    jne     .arg_next
    mov     qword ptr [rbp + LOC_HEADER], 1
.arg_next:
    inc     rax
    jmp     .arg_l
.arg_done:

    // Reserve the three mmap regions up front. Anonymous mmap is zero-filled, so
    // the column-width array starts cleared. rdi/rsi are clobbered by mmap, but
    // we take no arguments here, so nothing needs saving first.
    mov     rdi, ICAP_START
    call    uolt_mmap_anon
    test    rax, rax
    js      .nomem
    mov     r15, rax                    // input buffer base
    mov     qword ptr [rbp + LOC_ICAP], ICAP_START

    mov     rdi, OBUF_CAP
    call    uolt_mmap_anon
    test    rax, rax
    js      .nomem
    mov     r14, rax                    // output buffer base

    mov     rdi, COLW_BYTES
    call    uolt_mmap_anon
    test    rax, rax
    js      .nomem
    mov     rbx, rax                    // column-width array base (zero-filled)

    mov     qword ptr [rbp + LOC_NCOLS], 0
    mov     qword ptr [rbp + LOC_OLEN], 0
    mov     qword ptr [rbp + LOC_SEPDONE], 0

    // ---- slurp all of stdin into the growable input region ----
    xor     r13, r13                    // fill count
.rd:
    mov     rax, [rbp + LOC_ICAP]
    sub     rax, r13                     // free space in the buffer
    jnz     1f
    call    grow_input                  // full: grow, then keep reading
    mov     rax, [rbp + LOC_ICAP]
    sub     rax, r13
1:
    mov     rdx, rax
    mov     rdi, STDIN
    lea     rsi, [r15 + r13]
    call    uolt_read
    test    rax, rax
    jle     .eof                        // 0 = EOF, negative = error: stop
    add     r13, rax
    jmp     .rd
.eof:
    mov     [rbp + LOC_N], r13
    lea     rax, [r15 + r13]
    mov     [rbp + LOC_END], rax        // one past the last input byte

    // ---- pass 1: column count + per-column display widths ----
    mov     r12, r15                    // cur = start of input
.p1_line:
    mov     rax, [rbp + LOC_END]
    cmp     r12, rax
    jae     .p1_done
    // find this line's end (next '\n' or end of input)
    mov     rax, r12
    mov     rcx, [rbp + LOC_END]
.p1_fe:
    cmp     rax, rcx
    jae     .p1_have
    cmp     byte ptr [rax], 0x0a
    je      .p1_have
    inc     rax
    jmp     .p1_fe
.p1_have:
    mov     [rbp + LOC_LEND], rax
    mov     [rbp + LOC_P], r12          // field cursor = line start
    xor     r13, r13                    // column index for this line
.p1_fld:
    call    next_field                  // rax=start / -1, rdx=end
    cmp     rax, -1
    je      .p1_lineend
    mov     rdi, rax
    mov     rsi, rdx
    call    dispw                       // rax = display width
    cmp     r13, COLMAX
    jae     .too_many
    mov     rcx, [rbx + r13*8]          // current max for this column
    cmp     rax, rcx
    jbe     1f
    mov     [rbx + r13*8], rax
1:
    inc     r13
    jmp     .p1_fld
.p1_lineend:
    mov     rcx, [rbp + LOC_NCOLS]
    cmp     r13, rcx
    jbe     1f
    mov     [rbp + LOC_NCOLS], r13      // widen the table
1:
    // advance cur past the line (skip the '\n' if there was one)
    mov     rax, [rbp + LOC_LEND]
    mov     rcx, [rbp + LOC_END]
    cmp     rax, rcx
    jae     1f
    inc     rax
1:
    mov     r12, rax
    jmp     .p1_line
.p1_done:
    // No columns at all (empty or all-blank input): print nothing.
    cmp     qword ptr [rbp + LOC_NCOLS], 0
    je      .fin

    // ---- pass 2: draw the table ----
    lea     rdi, [rip + G_TL]           // top border  ┌───┬───┐
    lea     rsi, [rip + G_TT]
    lea     rdx, [rip + G_TR]
    call    hline

    // data rows
    mov     r12, r15                    // cur = start of input
.row_l:
    mov     rax, [rbp + LOC_END]
    cmp     r12, rax
    jae     .rows_done
    // find line end
    mov     rax, r12
    mov     rcx, [rbp + LOC_END]
.rl_fe:
    cmp     rax, rcx
    jae     .rl_have
    cmp     byte ptr [rax], 0x0a
    je      .rl_have
    inc     rax
    jmp     .rl_fe
.rl_have:
    mov     [rbp + LOC_LEND], rax
    // skip an entirely blank line (no non-blank byte) so it makes no row
    mov     rcx, r12
.rl_chk:
    cmp     rcx, rax
    jae     .rl_skip
    movzx   edx, byte ptr [rcx]
    cmp     dl, ' '
    je      1f
    cmp     dl, 0x09
    jne     .rl_emit
1:
    inc     rcx
    jmp     .rl_chk
.rl_skip:
    mov     rax, [rbp + LOC_LEND]
    mov     rcx, [rbp + LOC_END]
    cmp     rax, rcx
    jae     1f
    inc     rax
1:
    mov     r12, rax
    jmp     .row_l
.rl_emit:
    mov     [rbp + LOC_P], r12          // field cursor = line start
    xor     r13, r13                    // column index
.cell_l:
    mov     rax, [rbp + LOC_NCOLS]
    cmp     r13, rax
    jae     .cell_done
    lea     rsi, [rip + G_V]            // │ then a leading blank
    call    ob_g3
    mov     al, ' '
    call    ob_putb
    call    next_field                  // rax=start / -1, rdx=end
    cmp     rax, -1
    je      .cell_empty
    mov     [rbp + LOC_FS], rax
    mov     [rbp + LOC_FE], rdx
    // emit the field's bytes verbatim
    mov     rsi, rax
    mov     rdx, rdx
    sub     rdx, [rbp + LOC_FS]         // rdx = fend - fstart (== 0 impossible)
    call    ob_put
    // pad with blanks to the column width, then the trailing blank
    mov     rdi, [rbp + LOC_FS]
    mov     rsi, [rbp + LOC_FE]
    call    dispw                       // rax = this field's display width
    mov     rcx, [rbx + r13*8]
    sub     rcx, rax                     // pad count (>= 0)
    mov     rdi, rcx
    call    ob_sp
    jmp     .cell_pad
.cell_empty:
    // no field for this column: the whole cell interior is blanks
    mov     rdi, [rbx + r13*8]
    call    ob_sp
.cell_pad:
    mov     al, ' '
    call    ob_putb
    inc     r13
    jmp     .cell_l
.cell_done:
    lea     rsi, [rip + G_V]            // closing │
    call    ob_g3
    mov     al, 0x0a
    call    ob_putb
    // -H: after the first rendered row, draw the header separator once
    cmp     qword ptr [rbp + LOC_HEADER], 0
    je      .cell_adv
    cmp     qword ptr [rbp + LOC_SEPDONE], 0
    jne     .cell_adv
    mov     qword ptr [rbp + LOC_SEPDONE], 1
    lea     rdi, [rip + G_LT]           // ├───┼───┤
    lea     rsi, [rip + G_CR]
    lea     rdx, [rip + G_RT]
    call    hline
.cell_adv:
    // advance to the next line
    mov     rax, [rbp + LOC_LEND]
    mov     rcx, [rbp + LOC_END]
    cmp     rax, rcx
    jae     1f
    inc     rax
1:
    mov     r12, rax
    jmp     .row_l
.rows_done:
    lea     rdi, [rip + G_BL]           // bottom border  └───┴───┘
    lea     rsi, [rip + G_BT]
    lea     rdx, [rip + G_BR]
    call    hline

.fin:
    call    ob_flush
    xor     eax, eax
.ret:
    add     rsp, 176
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

// Out-of-memory (initial mmap or a grow failed): diagnose on stderr, exit 1.
// Unwinds through rbp so it also works when reached from grow_input.
.nomem:
    lea     rdi, [rip + err_nomem]
    call    err_puts
    mov     eax, 1
    lea     rsp, [rbp - 40]
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

// More than COLMAX columns on a line: refuse rather than silently drop data.
.too_many:
    lea     rdi, [rip + err_many]
    call    err_puts
    mov     eax, 1
    lea     rsp, [rbp - 40]
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

// grow_input(): double the input buffer, copy the r13 bytes held so far, unmap
// the old region, update r15 / LOC_ICAP. Preserves r13 (fill), r14 (output
// buffer), r15 is updated, rbx (column array). Only rax/rcx/rdx/rsi/rdi move.
grow_input:
    mov     rax, [rbp + LOC_ICAP]
    add     rax, rax
    mov     [rbp + LOC_NC], rax
    mov     rdi, rax
    call    uolt_mmap_anon
    test    rax, rax
    js      .nomem
    mov     [rbp + LOC_NB], rax
    mov     rdi, rax
    mov     rsi, r15
    mov     rcx, r13
    rep     movsb
    mov     rdi, r15
    mov     rsi, [rbp + LOC_ICAP]
    call    uolt_munmap
    mov     r15, [rbp + LOC_NB]
    mov     rax, [rbp + LOC_NC]
    mov     [rbp + LOC_ICAP], rax
    ret

// next_field() -> rax = field start pointer (or -1 if the line has no more
// fields), rdx = field end pointer. Advances LOC_P over the current line's
// blanks then the field's non-blanks. Uses only rax/rcx/rdx, so every caller's
// callee-saved registers (r12 cur, r13 col, r14, r15, rbx) survive.
next_field:
    mov     rax, [rbp + LOC_P]
    mov     rcx, [rbp + LOC_LEND]
.nf_ws:
    cmp     rax, rcx
    jae     .nf_none
    movzx   edx, byte ptr [rax]
    cmp     dl, ' '
    je      .nf_adv
    cmp     dl, 0x09
    jne     .nf_start
.nf_adv:
    inc     rax
    jmp     .nf_ws
.nf_start:
    mov     [rbp + LOC_FS], rax
.nf_nb:
    cmp     rax, rcx
    jae     .nf_end
    movzx   edx, byte ptr [rax]
    cmp     dl, ' '
    je      .nf_end
    cmp     dl, 0x09
    je      .nf_end
    inc     rax
    jmp     .nf_nb
.nf_end:
    mov     [rbp + LOC_P], rax
    mov     rdx, rax                    // field end
    mov     rax, [rbp + LOC_FS]         // field start
    ret
.nf_none:
    mov     [rbp + LOC_P], rax
    mov     rax, -1
    ret

// dispw(rdi = start, rsi = end) -> rax = number of UTF-8 code points in the
// byte range (count bytes that are not 10xxxxxx continuation bytes). Uses only
// rax/rcx/rdi, preserving r12/r13/r14/r15/rbx for the callers.
dispw:
    xor     eax, eax
.dw_l:
    cmp     rdi, rsi
    jae     .dw_done
    movzx   ecx, byte ptr [rdi]
    and     cl, 0xC0
    cmp     cl, 0x80
    je      .dw_skip
    inc     rax
.dw_skip:
    inc     rdi
    jmp     .dw_l
.dw_done:
    ret

// ---- buffered output helpers. All keep the output buffer in r14 and its fill
// in LOC_OLEN, and preserve r12/r13/r15/rbx so pass-2 loop state survives. ----

// ob_flush(): write out the buffered bytes and reset the fill.
ob_flush:
    mov     rdx, [rbp + LOC_OLEN]
    test    rdx, rdx
    jz      1f
    mov     rdi, STDOUT
    mov     rsi, r14
    call    uolt_write
    mov     qword ptr [rbp + LOC_OLEN], 0
1:
    ret

// ob_put(rsi = ptr, rdx = len): append len bytes, flushing as the buffer fills.
ob_put:
.op_l:
    test    rdx, rdx
    jz      .op_done
    mov     rax, OBUF_CAP
    sub     rax, [rbp + LOC_OLEN]        // free space
    jnz     1f
    push    rsi                          // flush clobbers rsi/rdx: save them
    push    rdx
    call    ob_flush
    pop     rdx
    pop     rsi
    mov     rax, OBUF_CAP
1:
    cmp     rax, rdx                     // k = min(space, len)
    jbe     2f
    mov     rax, rdx
2:
    mov     rdi, r14
    add     rdi, [rbp + LOC_OLEN]
    mov     rcx, rax
    push    rax
    rep     movsb                        // advances rsi and rdi by rax
    pop     rax
    add     [rbp + LOC_OLEN], rax
    sub     rdx, rax
    jmp     .op_l
.op_done:
    ret

// ob_putb(al = byte): append a single byte.
ob_putb:
    mov     rcx, [rbp + LOC_OLEN]
    cmp     rcx, OBUF_CAP
    jb      1f
    push    rax
    call    ob_flush
    pop     rax
    xor     rcx, rcx
1:
    mov     rdi, r14
    mov     byte ptr [rdi + rcx], al
    inc     rcx
    mov     [rbp + LOC_OLEN], rcx
    ret

// ob_g3(rsi = pointer to a 3-byte UTF-8 glyph): append it.
ob_g3:
    mov     rdx, 3
    jmp     ob_put

// ob_hrep(rdi = count): append the horizontal bar ─ count times.
ob_hrep:
    test    rdi, rdi
    jz      1f
    push    rdi
    lea     rsi, [rip + G_H]
    mov     rdx, 3
    call    ob_put
    pop     rdi
    dec     rdi
    jmp     ob_hrep
1:
    ret

// ob_sp(rdi = count): append count blanks.
ob_sp:
    test    rdi, rdi
    jz      1f
    push    rdi
    mov     al, ' '
    call    ob_putb
    pop     rdi
    dec     rdi
    jmp     ob_sp
1:
    ret

// hline(rdi = left glyph, rsi = mid glyph, rdx = right glyph): emit one
// horizontal rule spanning every column (left corner, per-column bars joined by
// the mid glyph, right corner), then a newline. Used for the top/bottom borders
// and the -H header separator. Preserves r12 (the line cursor) and rbx/r14/r15;
// clobbers r13. The three glyph pointers are stashed in locals because the ob_*
// calls clobber caller-saved registers.
hline:
    mov     [rbp + LOC_GL], rdi
    mov     [rbp + LOC_GM], rsi
    mov     [rbp + LOC_GR], rdx
    mov     rsi, rdi
    call    ob_g3                       // left corner
    xor     r13, r13
.hl_l:
    mov     rax, [rbp + LOC_NCOLS]
    cmp     r13, rax
    jae     .hl_done
    mov     rdi, [rbx + r13*8]
    add     rdi, 2                       // a blank of padding on each side
    call    ob_hrep
    mov     rax, [rbp + LOC_NCOLS]
    dec     rax
    cmp     r13, rax
    jae     .hl_last
    mov     rsi, [rbp + LOC_GM]
    call    ob_g3
    jmp     .hl_next
.hl_last:
    mov     rsi, [rbp + LOC_GR]
    call    ob_g3
.hl_next:
    inc     r13
    jmp     .hl_l
.hl_done:
    mov     al, 0x0a
    call    ob_putb
    ret

// err_puts(rdi = ASCIZ): write the string to stderr.
err_puts:
    mov     r10, rdi
    call    uolt_strlen
    mov     rdx, rax
    mov     rsi, r10
    mov     rdi, STDERR
    jmp     uolt_write

// Box-drawing glyphs (UTF-8, 3 bytes each) and diagnostics. Kept in .text after
// the code (reached rip-relative), matching the other tools' layout.
G_TL:  .byte 0xE2, 0x94, 0x8C          // ┌  U+250C
G_TR:  .byte 0xE2, 0x94, 0x90          // ┐  U+2510
G_BL:  .byte 0xE2, 0x94, 0x94          // └  U+2514
G_BR:  .byte 0xE2, 0x94, 0x98          // ┘  U+2518
G_H:   .byte 0xE2, 0x94, 0x80          // ─  U+2500
G_V:   .byte 0xE2, 0x94, 0x82          // │  U+2502
G_TT:  .byte 0xE2, 0x94, 0xAC          // ┬  U+252C
G_BT:  .byte 0xE2, 0x94, 0xB4          // ┴  U+2534
G_LT:  .byte 0xE2, 0x94, 0x9C          // ├  U+251C
G_CR:  .byte 0xE2, 0x94, 0xBC          // ┼  U+253C
G_RT:  .byte 0xE2, 0x94, 0xA4          // ┤  U+2524

err_many:  .asciz "uolt-table: too many columns\n"
err_nomem: .asciz "uolt-table: out of memory\n"
