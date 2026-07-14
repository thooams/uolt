// src/comm/comm.S - the POSIX `comm` utility.
//
// comm [-1] [-2] [-3] file1 file2: compare two sorted files line by line and
// write three tab-separated columns: lines only in file1, lines only in file2,
// and lines in both. -1/-2/-3 suppress the corresponding column; the tab
// indentation of a column is the number of non-suppressed columns before it.
//
// Both files are read fully into fixed buffers and split into line-pointer
// arrays on the stack (no heap, Principle IV; input beyond the buffer is
// dropped), then merged with a byte comparison.
//
// Called as uolt_main(argc in rdi, argv in rsi) by the per-OS entry shim.
//
// Layout at r15: buf1[TBUF] buf2[TBUF] ptr1[MAXL*8] ptr2[MAXL*8].
// Stack locals: [-48]=n1 [-56]=n2 [-64]=enable bits(1|2|4) [-72]=argc-1
//   [-80]=&argv [-88]=1-byte scratch.

#include "uolt.inc"

.set STDOUT, 1
.set STDERR, 2
.set O_RDONLY, 0
.set TBUF,   262144
.set MAXL,   32768

.set LOC_N1,    -48
.set LOC_N2,    -56
.set LOC_EN,    -64
.set LOC_ARGC,  -72
.set LOC_ARGV,  -80
.set LOC_CH,    -88

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
    sub     rsp, 2*TBUF + 2*MAXL*8 + 96
    mov     r15, rsp
    mov     qword ptr [rbp + LOC_EN], 7         // all columns enabled
    dec     rdi
    mov     [rbp + LOC_ARGC], rdi
    lea     rax, [rsi + 8]
    mov     [rbp + LOC_ARGV], rax

    mov     r12, rdi
    mov     r13, rax
.opt:
    test    r12, r12
    jz      .after
    mov     rbx, [r13]
    cmp     byte ptr [rbx], '-'
    jne     .after
    cmp     byte ptr [rbx + 1], 0
    je      .after
    cmp     byte ptr [rbx + 1], '-'
    je      .ddash
    lea     rdi, [rbx + 1]                      // handle combined flags, e.g. -12
.oflag:
    movzx   eax, byte ptr [rdi]
    test    al, al
    jz      .optnext
    cmp     al, '1'
    jne     1f
    and     qword ptr [rbp + LOC_EN], ~1
    jmp     .ofnext
1:
    cmp     al, '2'
    jne     2f
    and     qword ptr [rbp + LOC_EN], ~2
    jmp     .ofnext
2:
    cmp     al, '3'
    jne     .after                              // unknown flag letter -> stop
    and     qword ptr [rbp + LOC_EN], ~4
.ofnext:
    inc     rdi
    jmp     .oflag
.optnext:
    add     r13, 8
    dec     r12
    jmp     .opt
.ddash:
    cmp     byte ptr [rbx + 2], 0
    jne     .after
    add     r13, 8
    dec     r12
.after:
    cmp     r12, 2
    jne     .usage

    // read + split file1 -> ptr1, n1
    mov     rdi, [r13]
    lea     rsi, [r15]                          // buf1
    call    read_file
    js      .openerr
    lea     rdi, [r15]
    mov     rsi, rax                            // fill1
    lea     rdx, [r15 + 2*TBUF]                 // ptr1
    call    split_lines
    mov     [rbp + LOC_N1], rax

    // read + split file2 -> ptr2, n2
    mov     rdi, [r13 + 8]
    lea     rsi, [r15 + TBUF]                   // buf2
    call    read_file
    js      .openerr2
    lea     rdi, [r15 + TBUF]
    mov     rsi, rax
    lea     rdx, [r15 + 2*TBUF + MAXL*8]        // ptr2
    call    split_lines
    mov     [rbp + LOC_N2], rax

    // merge
    xor     r12, r12                            // i (file1)
    xor     r13, r13                            // j (file2)
.merge:
    mov     rax, [rbp + LOC_N1]
    cmp     r12, rax
    jae     .drain2
    mov     rax, [rbp + LOC_N2]
    cmp     r13, rax
    jae     .drain1
    lea     rax, [r15 + 2*TBUF]
    mov     rdi, [rax + r12*8]                  // line1[i]
    lea     rax, [r15 + 2*TBUF + MAXL*8]
    mov     rsi, [rax + r13*8]                  // line2[j]
    call    line_cmp
    test    rax, rax
    js      .only1
    jg      .only2
    // equal -> column 3 (both)
    lea     rax, [r15 + 2*TBUF]
    mov     rdi, [rax + r12*8]
    mov     rsi, 3
    call    emit_col
    inc     r12
    inc     r13
    jmp     .merge
.only1:
    lea     rax, [r15 + 2*TBUF]
    mov     rdi, [rax + r12*8]
    mov     rsi, 1
    call    emit_col
    inc     r12
    jmp     .merge
.only2:
    lea     rax, [r15 + 2*TBUF + MAXL*8]
    mov     rdi, [rax + r13*8]
    mov     rsi, 2
    call    emit_col
    inc     r13
    jmp     .merge
.drain1:
    mov     rax, [rbp + LOC_N1]
    cmp     r12, rax
    jae     .fin
    lea     rax, [r15 + 2*TBUF]
    mov     rdi, [rax + r12*8]
    mov     rsi, 1
    call    emit_col
    inc     r12
    jmp     .drain1
.drain2:
    mov     rax, [rbp + LOC_N2]
    cmp     r13, rax
    jae     .fin
    lea     rax, [r15 + 2*TBUF + MAXL*8]
    mov     rdi, [rax + r13*8]
    mov     rsi, 2
    call    emit_col
    inc     r13
    jmp     .drain2
.fin:
    xor     eax, eax
    jmp     .ret
.openerr:
    mov     rdi, [r13]
    jmp     .diag
.openerr2:
    mov     rdi, [r13 + 8]
.diag:
    push    rdi
    lea     rdi, [rip + err_pre]
    call    err_puts
    pop     rdi
    call    err_puts
    lea     rdi, [rip + err_suf]
    call    err_puts
    mov     eax, 1
    jmp     .ret
.usage:
    lea     rdi, [rip + err_usage]
    call    err_puts
    mov     eax, 1
.ret:
    add     rsp, 2*TBUF + 2*MAXL*8 + 96
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

// emit_col(rdi = line ptr, rsi = column 1/2/3): print the line in its column if
// that column is enabled, prefixed by a tab per enabled column before it.
emit_col:
    push    rbx
    push    r12
    mov     rbx, rdi                            // line
    mov     r12, rsi                            // column
    mov     rax, [rbp + LOC_EN]
    // is this column enabled? bit (col-1)
    mov     rcx, r12
    dec     rcx
    bt      rax, rcx
    jnc     .ec_ret
    // tabs = (enabled col < this col)
    xor     r8, r8                              // tab count
    test    rax, 1
    jz      1f
    cmp     r12, 1
    jle     1f
    inc     r8
1:
    test    rax, 2
    jz      2f
    cmp     r12, 2
    jle     2f
    inc     r8
2:
.ec_tab:
    test    r8, r8
    jz      .ec_line
    mov     byte ptr [rbp + LOC_CH], 0x09
    mov     rdi, STDOUT
    lea     rsi, [rbp + LOC_CH]
    mov     rdx, 1
    push    r8
    call    uolt_write
    pop     r8
    dec     r8
    jmp     .ec_tab
.ec_line:
    mov     rdi, rbx
    call    uolt_strlen
    mov     rdx, rax
    mov     rsi, rbx
    mov     rdi, STDOUT
    call    uolt_write
    mov     byte ptr [rbp + LOC_CH], 0x0a
    mov     rdi, STDOUT
    lea     rsi, [rbp + LOC_CH]
    mov     rdx, 1
    call    uolt_write
.ec_ret:
    pop     r12
    pop     rbx
    ret

// read_file(rdi = path, rsi = dest buffer) -> rax = bytes read (SF set on open
// error). Reads up to TBUF bytes.
read_file:
    push    rbx
    push    r12
    push    r13
    mov     r13, rsi                            // dest
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    call    uolt_open
    test    rax, rax
    js      .rf_err
    mov     rbx, rax                            // fd
    xor     r12, r12                            // fill
.rf_read:
    mov     rdx, TBUF
    sub     rdx, r12
    jz      .rf_close
    mov     rdi, rbx
    lea     rsi, [r13 + r12]
    call    uolt_read
    test    rax, rax
    jle     .rf_close
    add     r12, rax
    jmp     .rf_read
.rf_close:
    mov     rdi, rbx
    call    uolt_close
    mov     rax, r12                            // >= 0
    pop     r13
    pop     r12
    pop     rbx
    test    rax, rax                            // clear SF for the caller's `js`
    ret
.rf_err:
    mov     rax, -1                             // negative -> SF set at return site
    pop     r13
    pop     r12
    pop     rbx
    test    rax, rax
    ret

// split_lines(rdi = buf, rsi = length, rdx = ptr array) -> rax = line count.
// Replaces each newline with NUL and records line start pointers.
split_lines:
    push    rbx
    xor     rax, rax                            // count
    xor     rcx, rcx                            // i
.sl_line:
    cmp     rcx, rsi
    jae     .sl_done
    cmp     rax, MAXL
    jae     .sl_scan
    lea     rbx, [rdi + rcx]
    mov     [rdx + rax*8], rbx
    inc     rax
.sl_scan:
    cmp     rcx, rsi
    jae     .sl_done
    cmp     byte ptr [rdi + rcx], 0x0a
    je      .sl_nl
    inc     rcx
    jmp     .sl_scan
.sl_nl:
    mov     byte ptr [rdi + rcx], 0
    inc     rcx
    jmp     .sl_line
.sl_done:
    pop     rbx
    ret

// line_cmp(rdi, rsi) -> rax: byte comparison of NUL-terminated strings.
line_cmp:
    xor     rcx, rcx
1:
    movzx   eax, byte ptr [rdi + rcx]
    movzx   edx, byte ptr [rsi + rcx]
    cmp     eax, edx
    jne     2f
    test    eax, eax
    jz      3f
    inc     rcx
    jmp     1b
2:
    sub     eax, edx
    cdqe
    ret
3:
    xor     eax, eax
    ret

err_puts:
    mov     r10, rdi
    call    uolt_strlen
    mov     rdx, rax
    mov     rsi, r10
    mov     rdi, STDERR
    jmp     uolt_write

err_usage: .asciz "uolt-comm: usage: comm [-1] [-2] [-3] file1 file2\n"
err_pre:   .asciz "uolt-comm: "
err_suf:   .asciz ": cannot open\n"
