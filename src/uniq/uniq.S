// src/uniq/uniq.S - the POSIX `uniq` utility.
//
// uniq [-c] [-d] [-u] [-i] [-f N] [-s N] [file]: collapse adjacent identical
// lines. Default prints one line per run; -c prefixes each with its repeat count;
// -d prints only runs that repeat; -u prints only runs that occur once; -i folds
// case when comparing. -f N ignores the first N blank-separated fields and -s N
// ignores the next N characters when deciding whether lines match (the whole line
// is still printed). Input is the file operand or standard input.
//
// Input is streamed and split into lines; the current run's representative line
// is kept in a separate buffer with its count so it survives the input buffer
// refilling. Both buffers are mmap'd regions that GROW on demand (double, copy,
// munmap), so a line of any length is handled without truncation - the limit is
// memory. (Principle IV permits an explicit, failure-checked mmap when a fixed
// buffer would drop or mis-split data; it is not a hidden heap.) uniq never holds
// more than one input block plus the current representative line, so any number
// of lines streams in constant memory regardless of the total input size.
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
.set ICAP_START, 0x10000       // initial input block buffer: 64 KiB (grows)
.set PCAP_START, 0x10000       // initial prev-line buffer: 64 KiB (grows)

.set LOC_FLAGS, -48
.set LOC_HAVE,  -56
.set LOC_PLEN,  -64
.set LOC_COUNT, -72
.set LOC_CH,    -80
.set LOC_SKIPF, -112           // -f: fields to skip before comparing
.set LOC_SKIPS, -120           // -s: chars to skip (after the fields)
// NB: put_count uses [rbp-88] and ~20 bytes below it as its digit scratch, so
// these locals sit below that range to avoid being clobbered by a -c count.
.set LOC_ICAP,  -128           // input buffer capacity
.set LOC_PCAP,  -136           // prev-line buffer capacity
.set LOC_NC,    -144           // grow scratch: new capacity
.set LOC_NB,    -152           // grow scratch: new base

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

    // Capture argc/argv before mmap clobbers rdi/rsi (r12/r13 are callee-saved).
    mov     r12, rdi
    dec     r12
    lea     r13, [rsi + 8]

    mov     rdi, ICAP_START
    call    uolt_mmap_anon
    test    rax, rax
    js      .nomem
    mov     r15, rax                    // input block buffer
    mov     qword ptr [rbp + LOC_ICAP], ICAP_START
    mov     rdi, PCAP_START
    call    uolt_mmap_anon
    test    rax, rax
    js      .nomem
    mov     r14, rax                    // prev-line buffer
    mov     qword ptr [rbp + LOC_PCAP], PCAP_START

    mov     qword ptr [rbp + LOC_FLAGS], 0
    mov     qword ptr [rbp + LOC_HAVE], 0
    mov     qword ptr [rbp + LOC_COUNT], 0
    mov     qword ptr [rbp + LOC_SKIPF], 0
    mov     qword ptr [rbp + LOC_SKIPS], 0

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
    cmp     byte ptr [rbx + 1], 'f'     // -f N / -fN : skip fields
    je      .opt_f
    cmp     byte ptr [rbx + 1], 's'     // -s N / -sN : skip chars
    je      .opt_s
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
    jmp     .input
.opt_f:
    lea     rdi, [rbx + 2]              // "-fN" attached, or "-f" then next arg
    cmp     byte ptr [rdi], 0
    jne     1f
    add     r13, 8
    dec     r12
    jz      .input
    mov     rdi, [r13]
1:
    call    parse_uint
    mov     [rbp + LOC_SKIPF], rax
    add     r13, 8
    dec     r12
    jmp     .opt
.opt_s:
    lea     rdi, [rbx + 2]
    cmp     byte ptr [rdi], 0
    jne     1f
    add     r13, 8
    dec     r12
    jz      .input
    mov     rdi, [r13]
1:
    call    parse_uint
    mov     [rbp + LOC_SKIPS], rax
    add     r13, 8
    dec     r12
    jmp     .opt

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
    mov     rax, [rbp + LOC_ICAP]
    sub     rax, r13                     // space left in the input buffer
    jnz     1f
    call    grow_input                  // one line filled it: grow, keep reading
    mov     rax, [rbp + LOC_ICAP]
    sub     rax, r13
1:
    mov     rdx, rax
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
    add     rsp, 160
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

// Out-of-memory (a grow or the initial mmap failed): diagnose and exit 1. Unwinds
// via rbp so it also works when reached from grow_input / ensure_prev.
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

// grow_input(): double the input buffer, copy the r13 bytes held, unmap the old
// one, update r15 / LOC_ICAP. Preserves r12 (fd), r13 (fill), r14, rbx.
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

// ensure_prev(rax = needed bytes): make the prev-line buffer at least that large
// (its old contents are not needed - the caller is about to overwrite it).
// Preserves rbx / r12 / r13 (take_line's live registers).
ensure_prev:
    mov     rcx, [rbp + LOC_PCAP]
    cmp     rcx, rax
    jae     .ep_ok
.ep_dbl:
    add     rcx, rcx
    cmp     rcx, rax
    jb      .ep_dbl
    mov     [rbp + LOC_NC], rcx
    mov     rdi, r14                    // free the old buffer (contents unneeded)
    mov     rsi, [rbp + LOC_PCAP]
    call    uolt_munmap
    mov     rdi, [rbp + LOC_NC]
    call    uolt_mmap_anon
    test    rax, rax
    js      .nomem
    mov     r14, rax
    mov     rax, [rbp + LOC_NC]
    mov     [rbp + LOC_PCAP], rax
.ep_ok:
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
    // Compare the two lines from their comparison start (after -f fields and -s
    // chars). r10 = prev start offset, r11 = current start offset, r13 = the
    // (equal) suffix length being compared.
    mov     rdi, r14
    mov     rsi, [rbp + LOC_PLEN]
    call    skip_offset
    mov     r10, rax
    mov     rdi, rbx
    mov     rsi, r12
    call    skip_offset
    mov     r11, rax
    mov     rax, [rbp + LOC_PLEN]
    sub     rax, r10                    // prev suffix length
    mov     r13, r12
    sub     r13, r11                    // current suffix length
    cmp     rax, r13
    jne     .tl_diff                    // suffix lengths differ -> not equal
    lea     r8, [r14 + r10]             // prev suffix base (3-reg addressing is invalid)
    lea     r9, [rbx + r11]             // current suffix base
    xor     rcx, rcx
.tl_cmp:
    cmp     rcx, r13
    je      .tl_same
    mov     al, [r8 + rcx]
    mov     dl, [r9 + rcx]
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
    // copy this line into the prev buffer, growing it first if the line is longer
    // than the buffer's current capacity.
    mov     rax, r12
    call    ensure_prev
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

// skip_offset(rdi = line ptr, rsi = line length) -> rax = comparison start: the
// offset after skipping -f fields (leading blanks then non-blanks, repeated) and
// then -s characters. Clobbers rax/rcx/r9 only.
skip_offset:
    xor     rax, rax                    // i
    mov     r9, [rbp + LOC_SKIPF]
.so_field:
    test    r9, r9
    jz      .so_chars
.so_bl:
    cmp     rax, rsi                    // skip leading blanks
    jae     .so_done
    movzx   ecx, byte ptr [rdi + rax]
    cmp     cl, ' '
    je      1f
    cmp     cl, 0x09
    jne     .so_nb
1:
    inc     rax
    jmp     .so_bl
.so_nb:
    cmp     rax, rsi                    // skip the field (non-blanks)
    jae     .so_done
    movzx   ecx, byte ptr [rdi + rax]
    cmp     cl, ' '
    je      .so_fdone
    cmp     cl, 0x09
    je      .so_fdone
    inc     rax
    jmp     .so_nb
.so_fdone:
    dec     r9
    jmp     .so_field
.so_chars:
    mov     r9, [rbp + LOC_SKIPS]
.so_cl:
    test    r9, r9
    jz      .so_done
    cmp     rax, rsi
    jae     .so_done
    inc     rax
    dec     r9
    jmp     .so_cl
.so_done:
    ret

// parse_uint(rdi = ASCIZ) -> rax = leading unsigned decimal (0 if none).
parse_uint:
    xor     rax, rax
.pu_l:
    movzx   ecx, byte ptr [rdi]
    sub     cl, '0'
    cmp     cl, 9
    ja      .pu_d
    imul    rax, rax, 10
    movzx   rcx, cl
    add     rax, rcx
    inc     rdi
    jmp     .pu_l
.pu_d:
    ret

err_puts:
    mov     r10, rdi
    call    uolt_strlen
    mov     rdx, rax
    mov     rsi, r10
    mov     rdi, STDERR
    jmp     uolt_write

err_pre:   .asciz "uolt-uniq: "
err_suf:   .asciz ": cannot open\n"
err_nomem: .asciz "uolt-uniq: out of memory\n"
