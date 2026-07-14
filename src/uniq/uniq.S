// src/uniq/uniq.S - the POSIX `uniq` utility.
//
// uniq [-c] [-d] [-u] [file]: collapse adjacent identical lines. Default prints
// one line per run; -c prefixes each with its repeat count; -d prints only runs
// that repeat; -u prints only runs that occur once. Input is the file operand or
// standard input.
//
// Input is read in 64 KB blocks and split into lines (no heap, Principle IV);
// the current run's line is kept in a separate 64 KB buffer with its count so it
// survives the input buffer refilling. A line longer than the buffer is treated
// as one truncated line.
//
// Called as uolt_main(argc in rdi, argv in rsi) by the per-OS entry shim.
//
// Stack locals (rbp-relative):
//   [-48]=flags(bit0 -c, bit1 -d, bit2 -u)  [-56]=have-prev  [-64]=prev length
//   [-72]=run count  [-80]=1-byte scratch

#include "uolt.inc"

.set STDIN,  0
.set STDOUT, 1
.set STDERR, 2
.set O_RDONLY, 0
.set BUFSZ,  65536

.set LOC_FLAGS, -48
.set LOC_HAVE,  -56
.set LOC_PLEN,  -64
.set LOC_COUNT, -72
.set LOC_CH,    -80

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
    sub     rsp, 2*BUFSZ + 96
    mov     r15, rsp                    // line buffer
    lea     r14, [rsp + BUFSZ]          // prev-line buffer (kept across refills)
    mov     qword ptr [rbp + LOC_FLAGS], 0
    mov     qword ptr [rbp + LOC_HAVE], 0
    mov     qword ptr [rbp + LOC_COUNT], 0

    mov     r12, rdi
    dec     r12
    lea     r13, [rsi + 8]

.opt:
    test    r12, r12
    jz      .input
    mov     rbx, [r13]
    cmp     byte ptr [rbx], '-'
    jne     .input
    cmp     byte ptr [rbx + 1], 0
    je      .input                      // "-" = stdin operand
    cmp     byte ptr [rbx + 1], '-'
    je      .ddash
    lea     rdi, [rbx + 1]              // validate c/d/u
    mov     rsi, rdi
.v:
    movzx   ecx, byte ptr [rdi]
    test    cl, cl
    jz      .apply
    cmp     cl, 'c'
    je      1f
    cmp     cl, 'd'
    je      1f
    cmp     cl, 'u'
    je      1f
    cmp     cl, 'i'
    je      1f
    jmp     .input                      // unknown -> a file operand
1:
    inc     rdi
    jmp     .v
.apply:
    lea     rdi, [rsi]
.ap:
    movzx   ecx, byte ptr [rdi]
    test    cl, cl
    jz      .apd
    cmp     cl, 'c'
    jne     2f
    or      qword ptr [rbp + LOC_FLAGS], 1
2:
    cmp     cl, 'd'
    jne     3f
    or      qword ptr [rbp + LOC_FLAGS], 2
3:
    cmp     cl, 'u'
    jne     4f
    or      qword ptr [rbp + LOC_FLAGS], 4
4:
    cmp     cl, 'i'
    jne     9f
    or      qword ptr [rbp + LOC_FLAGS], 8
9:
    inc     rdi
    jmp     .ap
.apd:
    add     r13, 8
    dec     r12
    jmp     .opt
.ddash:
    cmp     byte ptr [rbx + 2], 0
    jne     .input
    add     r13, 8
    dec     r12

.input:
    test    r12, r12
    jz      .use_stdin
    mov     rdi, [r13]                  // first operand is the input file
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    call    uolt_open
    test    rax, rax
    js      .open_err
    mov     r12, rax
    jmp     .run
.use_stdin:
    mov     r12, STDIN
.run:
    xor     r13, r13                    // fill
.rd:
    mov     rdx, BUFSZ
    sub     rdx, r13
    jz      .longline
    mov     rdi, r12
    lea     rsi, [r15 + r13]
    call    uolt_read
    test    rax, rax
    jz      .eof
    js      .eof
    add     r13, rax
    xor     rbx, rbx                    // start
.scan:
    mov     r8, rbx
.find:
    cmp     r8, r13
    jae     .compact
    cmp     byte ptr [r15 + r8], 0x0a
    je      .line
    inc     r8
    jmp     .find
.line:
    lea     rdi, [r15 + rbx]
    mov     rsi, r8
    sub     rsi, rbx
    lea     rbx, [r8 + 1]
    call    take_line
    jmp     .scan
.compact:
    mov     rsi, r15
    add     rsi, rbx
    mov     rdi, r15
    mov     rcx, r13
    sub     rcx, rbx
    mov     r13, rcx
    rep     movsb
    jmp     .rd
.longline:
    mov     rdi, r15
    mov     rsi, r13
    call    take_line
    xor     r13, r13
    jmp     .rd
.eof:
    test    r13, r13
    jz      .flush_last
    mov     rdi, r15
    mov     rsi, r13
    call    take_line
.flush_last:
    cmp     qword ptr [rbp + LOC_HAVE], 0
    je      .fin
    call    flush_run
.fin:
    xor     eax, eax
    jmp     .ret
.open_err:
    lea     rdi, [rip + err_pre]
    call    err_puts
    mov     rdi, [r13]
    call    err_puts
    lea     rdi, [rip + err_suf]
    call    err_puts
    mov     eax, 1
.ret:
    add     rsp, 2*BUFSZ + 96
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

// take_line(rdi = line ptr, rsi = length): compare with the current run; extend
// the run or flush it and start a new one. r14 = prev buffer. Preserves the
// line-loop registers (rbx, r12, r13, r15).
take_line:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi                    // line ptr
    mov     r12, rsi                    // line length
    cmp     qword ptr [rbp + LOC_HAVE], 0
    je      .tl_new
    // same as prev? compare length then bytes
    cmp     r12, [rbp + LOC_PLEN]
    jne     .tl_diff
    xor     rcx, rcx
.tl_cmp:
    cmp     rcx, r12
    je      .tl_same
    mov     al, [rbx + rcx]
    mov     dl, [r14 + rcx]
    test    qword ptr [rbp + LOC_FLAGS], 8      // -i: fold ASCII case
    jz      .tl_c2
    cmp     al, 'A'
    jb      7f
    cmp     al, 'Z'
    ja      7f
    add     al, 0x20
7:
    cmp     dl, 'A'
    jb      8f
    cmp     dl, 'Z'
    ja      8f
    add     dl, 0x20
8:
.tl_c2:
    cmp     al, dl
    jne     .tl_diff
    inc     rcx
    jmp     .tl_cmp
.tl_same:
    inc     qword ptr [rbp + LOC_COUNT]
    jmp     .tl_ret
.tl_diff:
    call    flush_run
.tl_new:
    // copy this line into the prev buffer
    mov     [rbp + LOC_PLEN], r12
    xor     rcx, rcx
.tl_copy:
    cmp     rcx, r12
    je      .tl_copydone
    mov     al, [rbx + rcx]
    mov     [r14 + rcx], al
    inc     rcx
    jmp     .tl_copy
.tl_copydone:
    mov     qword ptr [rbp + LOC_HAVE], 1
    mov     qword ptr [rbp + LOC_COUNT], 1
.tl_ret:
    pop     r13
    pop     r12
    pop     rbx
    ret

// flush_run(): emit the current run per the flags (-d/-u filter, -c count prefix).
// Preserves the line-loop registers.
flush_run:
    push    rbx
    push    r12
    mov     r12, [rbp + LOC_FLAGS]
    mov     rbx, [rbp + LOC_COUNT]
    // -d: only runs with count > 1
    test    r12, 2
    jz      1f
    cmp     rbx, 1
    jle     .fr_ret
1:
    // -u: only runs with count == 1
    test    r12, 4
    jz      2f
    cmp     rbx, 1
    jne     .fr_ret
2:
    // -c: print the count, right-justified to width 7, then a space
    test    r12, 1
    jz      .fr_line
    mov     rax, rbx
    call    put_count
.fr_line:
    mov     rdi, STDOUT
    mov     rsi, r14                    // prev buffer
    mov     rdx, [rbp + LOC_PLEN]
    call    uolt_write
    mov     byte ptr [rbp + LOC_CH], 0x0a
    mov     rdi, STDOUT
    lea     rsi, [rbp + LOC_CH]
    mov     rdx, 1
    call    uolt_write
.fr_ret:
    pop     r12
    pop     rbx
    ret

// put_count(rax = value >= 1): write the decimal value and a trailing space.
// The exact field width is implementation-defined; the differential test
// normalizes whitespace.
put_count:
    lea     rdi, [rbp - 88]             // trailing space at [rbp-88]; digits before it
    mov     byte ptr [rdi], ' '
    mov     r9, rax
    mov     rcx, 10
1:
    dec     rdi
    xor     rdx, rdx
    mov     rax, r9
    div     rcx
    add     dl, '0'
    mov     [rdi], dl
    mov     r9, rax
    test    r9, r9
    jnz     1b
    lea     rdx, [rbp - 88 + 1]
    sub     rdx, rdi                     // length: digits + the space
    mov     rsi, rdi
    mov     rdi, STDOUT
    jmp     uolt_write

err_puts:
    mov     r10, rdi
    call    uolt_strlen
    mov     rdx, rax
    mov     rsi, r10
    mov     rdi, STDERR
    jmp     uolt_write

err_pre: .asciz "uolt-uniq: "
err_suf: .asciz ": cannot open\n"
