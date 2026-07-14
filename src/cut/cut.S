// src/cut/cut.S - the POSIX `cut` utility.
//
// cut -c LIST [file...]              select 1-based character positions
// cut -f LIST [-d DELIM] [file...]   select delimiter-separated fields
//
// LIST is a comma-separated list of positions and ranges: N, N-M, N- (to end of
// line), -M (from the start). For -f the default delimiter is a tab; a line with
// no delimiter is passed through unchanged (no -s). Selected positions live in a
// bitmap (plus an open-ended threshold) on the stack (no heap, Principle IV);
// input is read in 64 KB blocks and split into lines.
//
// Called as uolt_main(argc in rdi, argv in rsi) by the per-OS entry shim.
//
// Global registers: r15 = line buffer; the bitmap is at [r15 + BUFSZ]. Stack
// locals: [-48]=mode('c'/'f') [-56]=delimiter [-64]=to-end threshold
//   [-72]=exit status [-80]=1-byte scratch [-88]=argc-1 [-96]=&argv walk.

#include "uolt.inc"

.set STDIN,   0
.set STDOUT,  1
.set STDERR,  2
.set O_RDONLY, 0
.set BUFSZ,   65536
.set BITMAP,  1024                      // 8192 positions

.set LOC_MODE,  -48
.set LOC_DELIM, -56
.set LOC_TOEND, -64
.set LOC_STAT,  -72
.set LOC_CH,    -80
.set LOC_ARGC,  -88
.set LOC_ARGV,  -96

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
    sub     rsp, BUFSZ + BITMAP + 128
    mov     r15, rsp
    dec     rdi
    mov     [rbp + LOC_ARGC], rdi        // argc - 1
    lea     rax, [rsi + 8]
    mov     [rbp + LOC_ARGV], rax
    mov     qword ptr [rbp + LOC_MODE], 0
    mov     byte ptr [rbp + LOC_DELIM], 0x09
    mov     qword ptr [rbp + LOC_TOEND], 0
    mov     qword ptr [rbp + LOC_STAT], 0
    // clear the bitmap
    lea     rdi, [r15 + BUFSZ]
    xor     eax, eax
    mov     rcx, BITMAP/8
    rep     stosq

    mov     r12, [rbp + LOC_ARGC]
    mov     r13, [rbp + LOC_ARGV]
.opt:
    test    r12, r12
    jz      .after
    mov     rbx, [r13]
    cmp     byte ptr [rbx], '-'
    jne     .after
    cmp     byte ptr [rbx + 1], 0
    je      .after
    movzx   eax, byte ptr [rbx + 1]
    cmp     al, 'c'
    je      .opt_list
    cmp     al, 'f'
    je      .opt_list
    cmp     al, 'd'
    je      .opt_delim
    cmp     al, '-'
    je      .opt_ddash
    jmp     .after
.opt_list:
    mov     [rbp + LOC_MODE], al
    lea     rdi, [rbx + 2]
    cmp     byte ptr [rdi], 0
    jne     .have_list
    add     r13, 8
    dec     r12
    jz      .usage
    mov     rdi, [r13]
.have_list:
    call    parse_list
    add     r13, 8
    dec     r12
    jmp     .opt
.opt_delim:
    lea     rdi, [rbx + 2]
    cmp     byte ptr [rdi], 0
    jne     .have_delim
    add     r13, 8
    dec     r12
    jz      .usage
    mov     rdi, [r13]
.have_delim:
    mov     al, [rdi]
    mov     [rbp + LOC_DELIM], al
    add     r13, 8
    dec     r12
    jmp     .opt
.opt_ddash:
    cmp     byte ptr [rbx + 2], 0
    jne     .after
    add     r13, 8
    dec     r12
.after:
    cmp     qword ptr [rbp + LOC_MODE], 0
    je      .usage
    test    r12, r12
    jz      .use_stdin
.floop:
    test    r12, r12
    jz      .fin
    mov     rdi, [r13]
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    call    uolt_open
    test    rax, rax
    js      .fopenerr
    mov     rbx, rax
    mov     rdi, rbx
    call    run_fd
    mov     rdi, rbx
    call    uolt_close
    jmp     .fnext
.fopenerr:
    mov     qword ptr [rbp + LOC_STAT], 1
    lea     rdi, [rip + err_pre]
    call    err_puts
    mov     rdi, [r13]
    call    err_puts
    lea     rdi, [rip + err_suf]
    call    err_puts
.fnext:
    add     r13, 8
    dec     r12
    jmp     .floop
.use_stdin:
    mov     rdi, STDIN
    call    run_fd
.fin:
    mov     rax, [rbp + LOC_STAT]
    jmp     .ret
.usage:
    lea     rdi, [rip + err_usage]
    call    err_puts
    mov     rax, 1
.ret:
    add     rsp, BUFSZ + BITMAP + 128
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

// run_fd(rdi = fd): read the descriptor and cut each line. Uses the grep-style
// line loop (r12 = fd, r13 = fill, rbx = line start), all saved.
run_fd:
    push    rbx
    push    r12
    push    r13
    mov     r12, rdi
    xor     r13, r13
.rf_rd:
    mov     rdx, BUFSZ
    sub     rdx, r13
    jz      .rf_long
    mov     rdi, r12
    lea     rsi, [r15 + r13]
    call    uolt_read
    test    rax, rax
    jle     .rf_eof
    add     r13, rax
    xor     rbx, rbx
.rf_scan:
    mov     r8, rbx
.rf_find:
    cmp     r8, r13
    jae     .rf_compact
    cmp     byte ptr [r15 + r8], 0x0a
    je      .rf_line
    inc     r8
    jmp     .rf_find
.rf_line:
    lea     rdi, [r15 + rbx]
    mov     rsi, r8
    sub     rsi, rbx
    lea     rbx, [r8 + 1]
    call    cut_line
    jmp     .rf_scan
.rf_compact:
    mov     rsi, r15
    add     rsi, rbx
    mov     rdi, r15
    mov     rcx, r13
    sub     rcx, rbx
    mov     r13, rcx
    rep     movsb
    jmp     .rf_rd
.rf_long:
    lea     rdi, [r15]
    mov     rsi, r13
    call    cut_line
    xor     r13, r13
    jmp     .rf_rd
.rf_eof:
    test    r13, r13
    jz      .rf_ret
    lea     rdi, [r15]
    mov     rsi, r13
    call    cut_line
.rf_ret:
    pop     r13
    pop     r12
    pop     rbx
    ret

// cut_line(rdi = line ptr, rsi = length): emit the selected part + a newline.
// Preserves the line-loop registers (rbx/r12/r13/r15).
cut_line:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rdi                    // line ptr
    mov     r12, rsi                    // length
    cmp     byte ptr [rbp + LOC_MODE], 'f'
    je      .cl_fields
    // -c: emit selected character positions as contiguous runs
    xor     r13, r13                    // run start (1-based; 0 = no run)
    mov     r14, 1                      // position i (1-based)
.cl_c:
    cmp     r14, r12
    jg      .cl_c_end
    mov     rax, r14
    call    selected
    test    rax, rax
    jz      .cl_c_off
    test    r13, r13
    jnz     .cl_c_next
    mov     r13, r14                    // open a run
    jmp     .cl_c_next
.cl_c_off:
    call    .cl_flush_run
.cl_c_next:
    inc     r14
    jmp     .cl_c
.cl_c_end:
    call    .cl_flush_run
    jmp     .cl_nl
.cl_flush_run:
    test    r13, r13
    jz      .fr_done
    lea     rsi, [rbx + r13 - 1]        // run start byte
    mov     rdx, r14
    sub     rdx, r13                    // run length
    mov     rdi, STDOUT
    push    r14
    call    uolt_write
    pop     r14
    xor     r13, r13
.fr_done:
    ret

.cl_fields:
    // If the line has no delimiter, pass it through unchanged.
    movzx   ecx, byte ptr [rbp + LOC_DELIM]
    xor     r8, r8
.cl_hasd:
    cmp     r8, r12
    jae     .cl_whole
    cmp     byte ptr [rbx + r8], cl
    je      .cl_split
    inc     r8
    jmp     .cl_hasd
.cl_whole:
    mov     rsi, rbx
    mov     rdx, r12
    mov     rdi, STDOUT
    call    uolt_write
    jmp     .cl_nl
.cl_split:
    // walk fields; r13 = field index (1-based), r14 = field start, r9 = "output any"
    mov     r13, 1
    xor     r14, r14
    xor     r9, r9                      // any output yet
    xor     r8, r8                      // scan position
.cl_f:
    cmp     r8, r12
    jae     .cl_flast
    movzx   ecx, byte ptr [rbp + LOC_DELIM]
    cmp     byte ptr [rbx + r8], cl
    jne     .cl_f_next
    // end of a field at [r14, r8)
    mov     rax, r13
    call    selected
    test    rax, rax
    jz      1f
    call    .cl_emit_field              // field [r14, r8)
1:
    inc     r13
    lea     r14, [r8 + 1]
.cl_f_next:
    inc     r8
    jmp     .cl_f
.cl_flast:
    // last field [r14, r12)
    mov     rax, r13
    call    selected
    test    rax, rax
    jz      .cl_nl
    call    .cl_emit_field
    jmp     .cl_nl
.cl_emit_field:
    // emit a delimiter before every field except the first output one
    test    r9, r9
    jz      2f
    movzx   eax, byte ptr [rbp + LOC_DELIM]
    mov     [rbp + LOC_CH], al
    mov     rdi, STDOUT
    lea     rsi, [rbp + LOC_CH]
    mov     rdx, 1
    push    r14
    push    r8
    call    uolt_write
    pop     r8
    pop     r14
2:
    mov     r9, 1
    lea     rsi, [rbx + r14]
    mov     rdx, r8
    sub     rdx, r14                    // field length = current pos - field start
    push    r14
    push    r8
    push    r9
    mov     rdi, STDOUT
    call    uolt_write
    pop     r9
    pop     r8
    pop     r14
    ret

.cl_nl:
    mov     byte ptr [rbp + LOC_CH], 0x0a
    mov     rdi, STDOUT
    lea     rsi, [rbp + LOC_CH]
    mov     rdx, 1
    call    uolt_write
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

// selected(rax = 1-based position) -> rax = 1 if selected, else 0.
selected:
    mov     r11, [rbp + LOC_TOEND]
    test    r11, r11
    jz      1f
    cmp     rax, r11
    jae     .sel_yes
1:
    dec     rax
    cmp     rax, BITMAP*8
    jae     .sel_no
    mov     rcx, rax
    and     rcx, 7
    shr     rax, 3
    lea     rsi, [r15 + BUFSZ]
    movzx   edx, byte ptr [rsi + rax]
    shr     edx, cl
    and     edx, 1
    mov     rax, rdx
    ret
.sel_yes:
    mov     rax, 1
    ret
.sel_no:
    xor     rax, rax
    ret

// parse_list(rdi = LIST string): set the selected bits / open-end threshold.
parse_list:
.pl_next:
    movzx   eax, byte ptr [rdi]
    test    al, al
    jz      .pl_end
    xor     r8, r8                      // lo
    xor     r9, r9                      // lo present
.pl_lo:
    movzx   eax, byte ptr [rdi]
    sub     al, '0'
    cmp     al, 9
    ja      .pl_lo_done
    movzx   rax, al
    imul    r8, r8, 10
    add     r8, rax
    mov     r9, 1
    inc     rdi
    jmp     .pl_lo
.pl_lo_done:
    movzx   eax, byte ptr [rdi]
    cmp     al, '-'
    je      .pl_range
    test    r9, r9
    jz      .pl_skip
    mov     rax, r8
    call    set_bit
    jmp     .pl_skip
.pl_range:
    inc     rdi
    xor     r10, r10                    // hi
    xor     r11, r11                    // hi present
.pl_hi:
    movzx   eax, byte ptr [rdi]
    sub     al, '0'
    cmp     al, 9
    ja      .pl_hi_done
    movzx   rax, al
    imul    r10, r10, 10
    add     r10, rax
    mov     r11, 1
    inc     rdi
    jmp     .pl_hi
.pl_hi_done:
    test    r9, r9
    jnz     1f
    mov     r8, 1                       // "-M" -> lo defaults to 1
1:
    test    r11, r11
    jz      .pl_open
.pl_sr:
    cmp     r8, r10
    jg      .pl_skip
    mov     rax, r8
    call    set_bit
    inc     r8
    jmp     .pl_sr
.pl_open:
    mov     rax, [rbp + LOC_TOEND]
    test    rax, rax
    jz      2f
    cmp     r8, rax
    jae     .pl_skip
2:
    mov     [rbp + LOC_TOEND], r8
.pl_skip:
    movzx   eax, byte ptr [rdi]
    test    al, al
    jz      .pl_end
    cmp     al, ','
    je      3f
    inc     rdi
    jmp     .pl_skip
3:
    inc     rdi
    jmp     .pl_next
.pl_end:
    ret

// set_bit(rax = 1-based position): set the bit. Preserves rdi (the list ptr) and
// r8-r11 (parse_list state); uses rax/rcx/rdx/rsi.
set_bit:
    test    rax, rax
    jz      .sb_ret
    dec     rax
    cmp     rax, BITMAP*8
    jae     .sb_ret
    mov     rcx, rax
    and     rcx, 7
    shr     rax, 3
    mov     dl, 1
    shl     dl, cl
    lea     rsi, [r15 + BUFSZ]
    or      byte ptr [rsi + rax], dl
.sb_ret:
    ret

err_puts:
    mov     r10, rdi
    call    uolt_strlen
    mov     rdx, rax
    mov     rsi, r10
    mov     rdi, STDERR
    jmp     uolt_write

err_usage: .asciz "uolt-cut: usage: cut -c LIST | -f LIST [-d DELIM] [file...]\n"
err_pre:   .asciz "uolt-cut: "
err_suf:   .asciz ": cannot open\n"
