// extras/column/column.S - uolt-column: align whitespace-columned stdin into a
// padded table, like `column -t`.
//
// uolt-column reads standard input, splits each line into fields on runs of
// blanks (space / tab), and prints the fields aligned into columns: every field
// is padded with blanks to the widest field in its column and columns are
// separated by two blanks, exactly like BSD/util-linux `column -t`. The last
// field of each line is not padded (no trailing blanks), short lines simply emit
// the fields they have, and blank lines are dropped. Column widths are measured
// in UTF-8 code points, so accented text stays aligned (matching modern
// `column`).
//
//     $ ls -l | uolt-column -t
//     -rw-r--r--  1  thomas  1024  README.md
//     drwxr-xr-x  5  thomas  160   extras
//
// This is NOT a POSIX tool (`column` is util-linux / BSD, not POSIX): it belongs
// to the UOLT *extras* collection. It reuses the same sys/ + libuolt/
// infrastructure and obeys every UOLT principle except VIII (POSIX-only): pure
// x86_64 assembly, direct syscalls, no libc, no heap (its buffers are explicit,
// failure-checked mmap regions), size-targeted, tested and benchmarked.
//
// Only the `-t` (table) mode is implemented - the deterministic, useful one. The
// default multi-column "fill" mode of `column` depends on the terminal width and
// is not reproducible, so it is out of scope; a `-t` argument is accepted (and
// any other argument ignored) so `column -t` invocations work unchanged. Input
// is standard input only. -s (custom delimiter) is not implemented yet.
//
// Design: the whole of stdin is slurped
// into a growable anonymous mmap region (no fixed buffer that would truncate),
// then a first pass computes each column's display width and a second pass
// re-scans the same buffer and emits the padded columns through a 64 KiB output
// buffer. No per-row or per-field allocation.
//
// Called as uolt_main(argc in rdi, argv in rsi) by the per-OS entry shim.
//
// Stack locals (rbp-relative), all below -40 so they never overlap the five
// callee-saved registers the prologue pushes into [rbp-8..-40]:
//   [-48]=input capacity  [-56]=input length  [-64]=input end ptr
//   [-72]=output-buffer fill  [-80]=grow new-cap  [-88]=grow new-base
//   [-96]=current line end ptr  [-104]=field cursor ptr
//   [-112]=field start ptr  [-120]=field end ptr (next_field output)
//   [-128]=held field start  [-136]=held field end (the field awaiting a peek)

#include "uolt.inc"

.set STDIN,  0
.set STDOUT, 1
.set STDERR, 2

.set ICAP_START, 0x10000        // initial input buffer: 64 KiB (grows on demand)
.set OBUF_CAP,   0x10000        // output buffer: 64 KiB (flushed when full)
.set COLMAX,     1024           // max columns; beyond this we error out
.set COLW_BYTES, COLMAX * 8
.set COLGAP,     2              // blanks separating two columns (column -t)

.set LOC_ICAP,  -48
.set LOC_N,     -56
.set LOC_END,   -64
.set LOC_OLEN,  -72
.set LOC_NC,    -80
.set LOC_NB,    -88
.set LOC_LEND,  -96
.set LOC_P,     -104
.set LOC_FS,    -112
.set LOC_FE,    -120
.set LOC_CFS,   -128
.set LOC_CFE,   -136

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
    sub     rsp, 160
    cld

    // Reserve the three mmap regions up front. Anonymous mmap is zero-filled, so
    // the column-width array starts cleared. We take no meaningful arguments, so
    // nothing needs saving before mmap clobbers rdi/rsi.
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

    mov     qword ptr [rbp + LOC_OLEN], 0

    // ---- slurp all of stdin into the growable input region ----
    xor     r13, r13                    // fill count
.rd:
    mov     rax, [rbp + LOC_ICAP]
    sub     rax, r13
    jnz     1f
    call    grow_input
    mov     rax, [rbp + LOC_ICAP]
    sub     rax, r13
1:
    mov     rdx, rax
    mov     rdi, STDIN
    lea     rsi, [r15 + r13]
    call    uolt_read
    test    rax, rax
    jle     .eof
    add     r13, rax
    jmp     .rd
.eof:
    mov     [rbp + LOC_N], r13
    lea     rax, [r15 + r13]
    mov     [rbp + LOC_END], rax

    // ---- pass 1: per-column display widths ----
    mov     r12, r15                    // cur = start of input
.p1_line:
    mov     rax, [rbp + LOC_END]
    cmp     r12, rax
    jae     .p1_done
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
    mov     [rbp + LOC_P], r12
    xor     r13, r13                    // column index
.p1_fld:
    call    next_field
    cmp     rax, -1
    je      .p1_lineend
    mov     rdi, rax
    mov     rsi, rdx
    call    dispw                       // rax = display width
    cmp     r13, COLMAX
    jae     .too_many
    mov     rcx, [rbx + r13*8]
    cmp     rax, rcx
    jbe     1f
    mov     [rbx + r13*8], rax
1:
    inc     r13
    jmp     .p1_fld
.p1_lineend:
    mov     rax, [rbp + LOC_LEND]
    mov     rcx, [rbp + LOC_END]
    cmp     rax, rcx
    jae     1f
    inc     rax
1:
    mov     r12, rax
    jmp     .p1_line
.p1_done:

    // ---- pass 2: emit the aligned columns ----
    mov     r12, r15                    // cur = start of input
.row_l:
    mov     rax, [rbp + LOC_END]
    cmp     r12, rax
    jae     .done
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
    // drop an entirely blank line (no non-blank byte) - matches `column`
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
    call    next_field                  // first field (exists: line is non-blank)
    mov     [rbp + LOC_CFS], rax        // hold it while we peek the next one
    mov     [rbp + LOC_CFE], rdx
.cell_l:
    call    next_field                  // peek: is there a field after the held one?
    cmp     rax, -1
    je      .cell_last
    // Not the last field: emit the HELD field padded to its column width plus the
    // two-blank gap, then promote the peeked field to held.
    mov     [rbp + LOC_FS], rax         // ob_* clobber caller-saved: save the peek
    mov     [rbp + LOC_FE], rdx
    mov     rsi, [rbp + LOC_CFS]
    mov     rdx, [rbp + LOC_CFE]
    sub     rdx, rsi                     // held field length
    call    ob_put
    mov     rdi, [rbp + LOC_CFS]
    mov     rsi, [rbp + LOC_CFE]
    call    dispw                       // rax = held field display width
    mov     rcx, [rbx + r13*8]
    sub     rcx, rax                     // pad to the column width
    add     rcx, COLGAP                  // plus the inter-column gap
    mov     rdi, rcx
    call    ob_sp
    inc     r13
    mov     rax, [rbp + LOC_FS]
    mov     [rbp + LOC_CFS], rax
    mov     rax, [rbp + LOC_FE]
    mov     [rbp + LOC_CFE], rax
    jmp     .cell_l
.cell_last:
    // The held field is the line's last: emit it with no padding, then newline.
    mov     rsi, [rbp + LOC_CFS]
    mov     rdx, [rbp + LOC_CFE]
    sub     rdx, rsi
    call    ob_put
    mov     al, 0x0a
    call    ob_putb
    mov     rax, [rbp + LOC_LEND]
    mov     rcx, [rbp + LOC_END]
    cmp     rax, rcx
    jae     1f
    inc     rax
1:
    mov     r12, rax
    jmp     .row_l
.done:
    call    ob_flush
    xor     eax, eax
.ret:
    add     rsp, 160
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

// Out-of-memory (initial mmap or a grow failed): diagnose on stderr, exit 1.
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

// grow_input(): double the input buffer, copy the r13 bytes held, unmap the old
// region, update r15 / LOC_ICAP. Preserves r13/r14/rbx; only rax/rcx/rdx/rsi/rdi
// move.
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

// next_field() -> rax = field start pointer (or -1 if the current line has no
// more fields), rdx = field end pointer. Advances LOC_P over blanks then the
// field's non-blanks. Uses only rax/rcx/rdx, preserving the callers' r12/r13/
// r14/r15/rbx.
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
    mov     rdx, rax
    mov     rax, [rbp + LOC_FS]
    ret
.nf_none:
    mov     [rbp + LOC_P], rax
    mov     rax, -1
    ret

// dispw(rdi = start, rsi = end) -> rax = number of UTF-8 code points in the byte
// range (bytes that are not 10xxxxxx continuation bytes). Uses only rax/rcx/rdi.
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

// ---- buffered output. r14 = buffer, LOC_OLEN = fill. All preserve r12/r13/r15/
// rbx so the pass-2 loop state survives. ----

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
    sub     rax, [rbp + LOC_OLEN]
    jnz     1f
    push    rsi
    push    rdx
    call    ob_flush
    pop     rdx
    pop     rsi
    mov     rax, OBUF_CAP
1:
    cmp     rax, rdx
    jbe     2f
    mov     rax, rdx
2:
    mov     rdi, r14
    add     rdi, [rbp + LOC_OLEN]
    mov     rcx, rax
    push    rax
    rep     movsb
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

// err_puts(rdi = ASCIZ): write the string to stderr.
err_puts:
    mov     r10, rdi
    call    uolt_strlen
    mov     rdx, rax
    mov     rsi, r10
    mov     rdi, STDERR
    jmp     uolt_write

err_many:  .asciz "uolt-column: too many columns\n"
err_nomem: .asciz "uolt-column: out of memory\n"
