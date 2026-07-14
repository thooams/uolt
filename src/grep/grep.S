// src/grep/grep.S - the `grep` utility (fixed-string match).
//
// grep [-ivncwx] pattern [file...]: print input lines that contain `pattern` as
// a literal substring. -i matches case-insensitively; -v prints the non-matching
// lines; -n prefixes line numbers; -c prints only a match count; -w requires the
// match to fall on word boundaries; -x requires the whole line to equal the
// pattern. With no file (or only stdin) lines are read from standard input; with
// more than one file each matching line is prefixed with "file:". Regular
// expressions and the many other grep options are out of scope in v1 (this is a
// fixed-string matcher, like `grep -F`).
//
// Input is read in 64 KB blocks into a line buffer and split on newlines (no
// heap, Principle IV); a line longer than the buffer is matched in one truncated
// piece. Exit status follows grep: 0 if any line matched, 1 if none, 2 on error.
//
// Called as uolt_main(argc in rdi, argv in rsi) by the per-OS entry shim.
//
// Stack locals (rbp-relative):
//   [-48]=pattern ptr  [-56]=pattern len  [-64]=flags(bit0 -i, bit1 -v)
//   [-72]=name ptr or 0  [-80]=any-match  [-88]=error  [-96]=1-byte scratch

#include "uolt.inc"

.set STDIN,  0
.set STDOUT, 1
.set STDERR, 2
.set BUFSZ,  65536

.set LOC_PAT,    -48
.set LOC_PATLEN, -56
.set LOC_FLAGS,  -64
.set LOC_NAME,   -72
.set LOC_MATCH,  -80
.set LOC_ERR,    -88
.set LOC_CH,     -96
.set LOC_LINENO, -104
.set LOC_COUNT,  -112
.set LOC_NUM,    -136
.set LOC_XLEN,   -144       // saved original line length (for -w/-x)

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
    sub     rsp, BUFSZ + 160
    mov     r15, rsp
    mov     qword ptr [rbp + LOC_FLAGS], 0
    mov     qword ptr [rbp + LOC_MATCH], 0
    mov     qword ptr [rbp + LOC_ERR], 0

    mov     r12, rdi
    dec     r12
    lea     r13, [rsi + 8]

.opt:
    test    r12, r12
    jz      .usage
    mov     rbx, [r13]
    cmp     byte ptr [rbx], '-'
    jne     .have_pat
    cmp     byte ptr [rbx + 1], 0
    je      .have_pat               // "-" alone is a pattern here
    cmp     byte ptr [rbx + 1], '-'
    je      .ddash
    lea     rdi, [rbx + 1]          // validate letters are i/v
    mov     rsi, rdi
.v:
    movzx   ecx, byte ptr [rdi]
    test    cl, cl
    jz      .apply
    cmp     cl, 'i'
    je      1f
    cmp     cl, 'v'
    je      1f
    cmp     cl, 'n'
    je      1f
    cmp     cl, 'c'
    je      1f
    cmp     cl, 'w'
    je      1f
    cmp     cl, 'x'
    je      1f
    jmp     .have_pat               // unknown -> treat as the pattern
1:
    inc     rdi
    jmp     .v
.apply:
    lea     rdi, [rsi]
.ap:
    movzx   ecx, byte ptr [rdi]
    test    cl, cl
    jz      .apd
    cmp     cl, 'i'
    jne     2f
    or      qword ptr [rbp + LOC_FLAGS], 1
2:
    cmp     cl, 'v'
    jne     3f
    or      qword ptr [rbp + LOC_FLAGS], 2
3:
    cmp     cl, 'n'
    jne     7f
    or      qword ptr [rbp + LOC_FLAGS], 4
7:
    cmp     cl, 'c'
    jne     8f
    or      qword ptr [rbp + LOC_FLAGS], 8
8:
    cmp     cl, 'w'
    jne     9f
    or      qword ptr [rbp + LOC_FLAGS], 16
9:
    cmp     cl, 'x'
    jne     10f
    or      qword ptr [rbp + LOC_FLAGS], 32
10:
    inc     rdi
    jmp     .ap
.apd:
    add     r13, 8
    dec     r12
    jmp     .opt
.ddash:
    cmp     byte ptr [rbx + 2], 0
    jne     .have_pat
    add     r13, 8
    dec     r12

.have_pat:
    test    r12, r12
    jz      .usage
    mov     rax, [r13]
    mov     [rbp + LOC_PAT], rax
    mov     rdi, rax
    call    uolt_strlen
    mov     [rbp + LOC_PATLEN], rax
    add     r13, 8
    dec     r12

    test    r12, r12
    jnz     .files
    // no file operands: read standard input, no name prefix
    mov     qword ptr [rbp + LOC_NAME], 0
    mov     rdi, STDIN
    call    grep_fd
    jmp     .fin

.files:
    // prefix names only when more than one file
    cmp     r12, 1
    setg    al
    movzx   rax, al                 // 1 if multi
    mov     r14, rax                // multi flag (callee-saved)
.floop:
    test    r12, r12
    jz      .fin
    mov     rbx, [r13]
    mov     rdi, rbx
    xor     rsi, rsi
    xor     rdx, rdx
    call    uolt_open
    test    rax, rax
    js      .fopenerr
    push    rax                     // fd
    test    r14, r14
    jz      4f
    mov     [rbp + LOC_NAME], rbx
    jmp     5f
4:
    mov     qword ptr [rbp + LOC_NAME], 0
5:
    mov     rdi, [rsp]              // fd
    call    grep_fd
    pop     rdi                     // fd
    call    uolt_close
    jmp     .fnext
.fopenerr:
    mov     qword ptr [rbp + LOC_ERR], 1
    lea     rdi, [rip + err_pre]
    call    err_puts
    mov     rdi, rbx
    call    err_puts
    lea     rdi, [rip + err_suf]
    call    err_puts
.fnext:
    add     r13, 8
    dec     r12
    jmp     .floop

.fin:
    cmp     qword ptr [rbp + LOC_ERR], 0
    jne     .ex2
    cmp     qword ptr [rbp + LOC_MATCH], 0
    jne     .ex0
    mov     eax, 1                  // no matches
    jmp     .ret
.ex0:
    xor     eax, eax
    jmp     .ret
.ex2:
    mov     eax, 2
.ret:
    add     rsp, BUFSZ + 160
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
.usage:
    lea     rdi, [rip + err_usage]
    call    err_puts
    mov     eax, 2
    add     rsp, BUFSZ + 160
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

// grep_fd(fd in rdi): read the descriptor, split into lines, print matches.
grep_fd:
    push    rbx
    push    r12
    push    r13
    mov     r12, rdi                // fd
    xor     r13, r13                // fill (bytes held in the line buffer)
    mov     qword ptr [rbp + LOC_LINENO], 0
    mov     qword ptr [rbp + LOC_COUNT], 0
.gf_read:
    mov     rdx, BUFSZ
    sub     rdx, r13
    jz      .gf_longline            // buffer full with no newline: flush it
    mov     rdi, r12
    lea     rsi, [r15 + r13]
    call    uolt_read
    test    rax, rax
    jz      .gf_eof
    js      .gf_readerr
    add     r13, rax
    xor     rbx, rbx                // start of the current line
.gf_scan:
    mov     r8, rbx
.gf_find:
    cmp     r8, r13
    jae     .gf_compact
    cmp     byte ptr [r15 + r8], 0x0a
    je      .gf_line
    inc     r8
    jmp     .gf_find
.gf_line:
    lea     rdi, [r15 + rbx]
    mov     rsi, r8
    sub     rsi, rbx                // line length (excluding newline)
    lea     rbx, [r8 + 1]           // next line starts after the newline
    call    process_line
    jmp     .gf_scan
.gf_compact:
    // move the leftover partial line [rbx, fill) to the front
    mov     rsi, r15
    add     rsi, rbx
    mov     rdi, r15
    mov     rcx, r13
    sub     rcx, rbx
    mov     r13, rcx
    rep     movsb
    jmp     .gf_read
.gf_longline:
    lea     rdi, [r15]
    mov     rsi, r13
    call    process_line
    xor     r13, r13
    jmp     .gf_read
.gf_eof:
    test    r13, r13
    jz      .gf_done
    lea     rdi, [r15]              // final line without a trailing newline
    mov     rsi, r13
    call    process_line
.gf_done:
    test    qword ptr [rbp + LOC_FLAGS], 8      // -c: print the match count
    jz      .gfd_ret
    mov     rax, [rbp + LOC_NAME]
    test    rax, rax
    jz      .gfd_nn
    mov     rdi, rax
    call    put_str
    mov     al, ':'
    call    put_char
.gfd_nn:
    mov     rax, [rbp + LOC_COUNT]
    call    put_uint
    mov     al, 0x0a
    call    put_char
.gfd_ret:
    pop     r13
    pop     r12
    pop     rbx
    ret
.gf_readerr:
    mov     qword ptr [rbp + LOC_ERR], 1
    pop     r13
    pop     r12
    pop     rbx
    ret

// process_line(rdi = line ptr, rsi = line length): test the match and, if it
// matches (accounting for -v), print the line with any name prefix. Preserves
// rbx/r12/r13/r15.
process_line:
    inc     qword ptr [rbp + LOC_LINENO]        // count every line
    push    rdi
    push    rsi
    mov     rdx, [rbp + LOC_PAT]
    mov     rcx, [rbp + LOC_PATLEN]
    mov     r8, [rbp + LOC_FLAGS]
    and     r8, 1                   // -i
    call    contains                // -> rax = 1/0
    mov     r9, [rbp + LOC_FLAGS]
    test    r9, 2                   // -v inverts
    jz      1f
    xor     rax, 1
1:
    pop     rsi
    pop     rdi
    test    rax, rax
    jz      .pl_done
    mov     qword ptr [rbp + LOC_MATCH], 1
    // -c: count only, no line output
    test    qword ptr [rbp + LOC_FLAGS], 8
    jz      .pl_print
    inc     qword ptr [rbp + LOC_COUNT]
    jmp     .pl_done
.pl_print:
    // optional "name:" prefix
    mov     rax, [rbp + LOC_NAME]
    test    rax, rax
    jz      .pl_noname
    push    rdi
    push    rsi
    mov     rdi, rax
    call    put_str
    mov     al, ':'
    call    put_char
    pop     rsi
    pop     rdi
.pl_noname:
    // optional "lineno:" prefix (-n)
    test    qword ptr [rbp + LOC_FLAGS], 4
    jz      .pl_noln
    push    rdi
    push    rsi
    mov     rax, [rbp + LOC_LINENO]
    call    put_uint
    mov     al, ':'
    call    put_char
    pop     rsi
    pop     rdi
.pl_noln:
    mov     rdx, rsi                // write the line
    mov     rsi, rdi
    mov     rdi, STDOUT
    call    uolt_write
    mov     al, 0x0a
    call    put_char
.pl_done:
    ret

// contains(rdi=line, rsi=len, rdx=pat, rcx=patlen, r8=ci) -> rax = 1 if the
// pattern occurs in the line (case-insensitively when ci). Naive scan.
contains:
    push    rbx
    mov     [rbp + LOC_XLEN], rsi   // save the original line length
    test    qword ptr [rbp + LOC_FLAGS], 32     // -x: whole-line match
    jnz     .ct_exact
    test    rcx, rcx
    jz      .ct_yes                 // empty pattern matches every line
    mov     r9, rsi
    sub     r9, rcx                 // last possible start index
    js      .ct_no                  // line shorter than the pattern
    xor     r10, r10                // i
.ct_out:
    cmp     r10, r9
    jg      .ct_no
    lea     rsi, [rdi + r10]        // base = &line[i] (len saved in LOC_XLEN)
    xor     r11, r11                // j
.ct_in:
    cmp     r11, rcx
    je      .ct_matched             // matched the whole pattern
    mov     al, [rsi + r11]
    mov     bl, [rdx + r11]
    test    r8, r8
    jz      .ct_cmp
    cmp     al, 'A'
    jb      6f
    cmp     al, 'Z'
    ja      6f
    add     al, 0x20
6:
    cmp     bl, 'A'
    jb      7f
    cmp     bl, 'Z'
    ja      7f
    add     bl, 0x20
7:
.ct_cmp:
    cmp     al, bl
    jne     .ct_next
    inc     r11
    jmp     .ct_in
.ct_matched:
    test    qword ptr [rbp + LOC_FLAGS], 16     // -w: require word boundaries
    jz      .ct_yes
    // left edge: start of line or a non-word char before the match
    test    r10, r10
    jz      .cw_left
    mov     al, [rdi + r10 - 1]
    call    is_word
    test    rax, rax
    jnz     .ct_next                // word char to the left -> not a whole word
.cw_left:
    // right edge: end of line or a non-word char after the match
    mov     rax, r10
    add     rax, rcx                // index just past the match
    cmp     rax, [rbp + LOC_XLEN]
    jae     .ct_yes
    mov     al, [rdi + rax]
    call    is_word
    test    rax, rax
    jnz     .ct_next
    jmp     .ct_yes
.ct_next:
    inc     r10
    jmp     .ct_out
.ct_exact:
    // -x: the line must equal the pattern (folded under -i).
    cmp     rsi, rcx                // lengths differ -> no match
    jne     .ct_no
    xor     r10, r10
.cx_lp:
    cmp     r10, rcx
    je      .ct_yes
    mov     al, [rdi + r10]
    mov     bl, [rdx + r10]
    test    r8, r8
    jz      .cx_cmp
    cmp     al, 'A'
    jb      3f
    cmp     al, 'Z'
    ja      3f
    add     al, 0x20
3:
    cmp     bl, 'A'
    jb      4f
    cmp     bl, 'Z'
    ja      4f
    add     bl, 0x20
4:
.cx_cmp:
    cmp     al, bl
    jne     .ct_no
    inc     r10
    jmp     .cx_lp
.ct_yes:
    mov     rax, 1
    pop     rbx
    ret
.ct_no:
    xor     rax, rax
    pop     rbx
    ret

// is_word(al) -> rax = 1 if al is a word character [A-Za-z0-9_], else 0.
// Clobbers rax only.
is_word:
    cmp     al, '0'
    jb      9f
    cmp     al, '9'
    jbe     8f
    cmp     al, 'A'
    jb      9f
    cmp     al, 'Z'
    jbe     8f
    cmp     al, 'a'
    jb      1f
    cmp     al, 'z'
    jbe     8f
    jmp     9f
1:
    cmp     al, '_'
    je      8f
9:
    xor     eax, eax
    ret
8:
    mov     eax, 1
    ret

// put_char(al): write one byte to stdout.
put_char:
    mov     [rbp + LOC_CH], al
    mov     rdi, STDOUT
    lea     rsi, [rbp + LOC_CH]
    mov     rdx, 1
    jmp     uolt_write

// put_uint(rax = value): write the unsigned decimal to stdout.
put_uint:
    lea     rdi, [rbp + LOC_NUM + 20]
    test    rax, rax
    jnz     1f
    dec     rdi
    mov     byte ptr [rdi], '0'
    jmp     2f
1:
    mov     r11, rax
    mov     rcx, 10
.pu_lp:
    test    r11, r11
    jz      2f
    mov     rax, r11
    xor     rdx, rdx
    div     rcx
    add     dl, '0'
    dec     rdi
    mov     [rdi], dl
    mov     r11, rax
    jmp     .pu_lp
2:
    lea     rdx, [rbp + LOC_NUM + 20]
    sub     rdx, rdi
    mov     rsi, rdi
    mov     rdi, STDOUT
    jmp     uolt_write

// put_str(rdi = ASCIZ): write the string to stdout.
put_str:
    mov     r10, rdi
    call    uolt_strlen
    mov     rdx, rax
    mov     rsi, r10
    mov     rdi, STDOUT
    jmp     uolt_write

err_puts:
    mov     r10, rdi
    call    uolt_strlen
    mov     rdx, rax
    mov     rsi, r10
    mov     rdi, STDERR
    jmp     uolt_write

err_usage: .asciz "uolt-grep: usage: grep [-ivncwx] pattern [file...]\n"
err_pre:   .asciz "uolt-grep: "
err_suf:   .asciz ": cannot open\n"
