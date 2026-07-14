// src/wc/wc.S - uolt-wc: the POSIX `wc` utility.
//
// Counts lines, words, bytes, and characters of each file operand, or of
// standard input. Options -l, -w, -c, -m select which counts to print (combinable
// as -lwc or as separate flags); with none given, lines/words/bytes are printed.
// The counts are always emitted in the order lines, words, chars, bytes -
// regardless of the order the flags were given - followed by the file name. With
// more than one file operand a final "total" line sums the columns. In the C
// locale a character is a byte, so -m equals -c numerically.
//
// The exact column spacing of `wc` is implementation-defined and differs between
// GNU (dynamic width) and BSD (fixed width); this tool prints one space between
// fields with no padding. A "word" is a maximal run of non-<blank> bytes, where
// <blank> is space, tab, newline, vertical tab, form feed, or carriage return
// (the C-locale isspace set). Bytes are counted as read; the stdin operand "-"
// is out of scope in v1 (POSIX-minimal, Principle VIII).
//
// Called as uolt_main(argc in rdi, argv in rsi). A file that cannot be opened
// yields a stderr diagnostic, sets the exit status to 1, and does not stop the
// remaining operands. No heap (Principle IV): input flows through one 64 KB stack
// buffer and the counts live in registers / stack locals.
//
// uolt_main register roles (callee-saved):
//   r12 = show mask (bit0 = lines, bit1 = words, bit2 = bytes)
//   r13 = pointer to the current argv entry
//   r14 = accumulated exit status
//   r15 = base of the 64 KB read buffer
//   rbx = scratch: current operand string, then the open file descriptor

#include "uolt.inc"

.set STDIN,    0
.set STDOUT,   1
.set STDERR,   2
.set O_RDONLY, 0
.set BUFSZ,    65536

.set LOC_L,     -48             // current line count
.set LOC_W,     -56             // current word count
.set LOC_C,     -64             // current byte count
.set LOC_TL,    -72             // total lines
.set LOC_TW,    -80             // total words
.set LOC_TC,    -88             // total bytes
.set LOC_REM,   -96             // remaining operand count
.set LOC_MULTI, -104            // 1 if more than one operand (print a total)
.set LOC_FF,    -112            // "first field" flag while emitting a line
.set LOC_CH,    -120            // one-byte scratch for put_char
.set LOC_NUM,   -144            // 20-byte scratch for decimal formatting

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
    sub     rsp, BUFSZ + 192
    mov     r15, rsp
    xor     r14, r14

    // --- Option parsing: build the show mask, advance to operands. ---
    xor     r12, r12            // no flags yet
    mov     r13, rsi
    add     r13, 8              // &argv[1]
    mov     rcx, rdi
    dec     rcx

.opt:
    test    rcx, rcx
    jz      .opt_done
    mov     rbx, [r13]
    cmp     byte ptr [rbx], '-'
    jne     .opt_done
    cmp     byte ptr [rbx + 1], 0
    je      .opt_done           // "-" -> treated as an operand (no v1 stdin alias)
    cmp     byte ptr [rbx + 1], '-'
    jne     .parse_flags
    cmp     byte ptr [rbx + 2], 0
    jne     .parse_flags
    add     r13, 8              // "--": end of options
    dec     rcx
    jmp     .opt_done
.parse_flags:
    lea     rsi, [rbx + 1]      // validate every letter is l/w/c first
    mov     rdi, rsi
.val:
    movzx   eax, byte ptr [rdi]
    test    al, al
    jz      .apply
    cmp     al, 'l'
    je      1f
    cmp     al, 'w'
    je      1f
    cmp     al, 'c'
    je      1f
    cmp     al, 'm'
    je      1f
    jmp     .opt_done           // unknown letter -> this arg is an operand
1:
    inc     rdi
    jmp     .val
.apply:
    mov     rdi, rsi
.ap:
    movzx   eax, byte ptr [rdi]
    test    al, al
    jz      .ap_done
    cmp     al, 'l'
    jne     2f
    or      r12, 1
2:
    cmp     al, 'w'
    jne     3f
    or      r12, 2
3:
    cmp     al, 'c'
    jne     5f
    or      r12, 4
5:
    cmp     al, 'm'
    jne     4f
    or      r12, 8              // -m: characters (= bytes in the C locale)
4:
    inc     rdi
    jmp     .ap
.ap_done:
    add     r13, 8
    dec     rcx
    jmp     .opt

.opt_done:
    test    r12, r12
    jnz     1f
    mov     r12, 7              // default: lines, words, bytes
1:
    mov     [rbp + LOC_REM], rcx
    xor     rax, rax
    mov     [rbp + LOC_TL], rax
    mov     [rbp + LOC_TW], rax
    mov     [rbp + LOC_TC], rax
    mov     qword ptr [rbp + LOC_MULTI], 0
    cmp     rcx, 1
    jbe     2f
    mov     qword ptr [rbp + LOC_MULTI], 1
2:
    test    rcx, rcx
    jnz     .have

    // No operand -> count standard input, no name.
    mov     rbx, STDIN
    call    count_fd
    mov     [rbp + LOC_L], r8
    mov     [rbp + LOC_W], r9
    mov     [rbp + LOC_C], r10
    xor     rsi, rsi
    call    emit_line
    jmp     .finish

.have:
.ploop:
    cmp     qword ptr [rbp + LOC_REM], 0
    je      .totals
    mov     rbx, [r13]
    mov     rdi, rbx
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    call    uolt_open
    test    rax, rax
    js      .wf_err
    mov     rbx, rax            // fd
    call    count_fd            // -> r8 lines, r9 words, r10 bytes
    mov     rdi, rbx
    call    uolt_close
    mov     [rbp + LOC_L], r8
    mov     [rbp + LOC_W], r9
    mov     [rbp + LOC_C], r10
    mov     rax, [rbp + LOC_TL]
    add     rax, r8
    mov     [rbp + LOC_TL], rax
    mov     rax, [rbp + LOC_TW]
    add     rax, r9
    mov     [rbp + LOC_TW], rax
    mov     rax, [rbp + LOC_TC]
    add     rax, r10
    mov     [rbp + LOC_TC], rax
    mov     rsi, [r13]          // name
    call    emit_line
    jmp     .wnext
.wf_err:
    mov     r14, 1
    lea     rdi, [rip + err_pre]
    call    err_puts
    mov     rdi, [r13]
    call    err_puts
    lea     rdi, [rip + err_suf]
    call    err_puts
.wnext:
    add     r13, 8
    dec     qword ptr [rbp + LOC_REM]
    jmp     .ploop

.totals:
    cmp     qword ptr [rbp + LOC_MULTI], 0
    je      .finish
    mov     rax, [rbp + LOC_TL]
    mov     [rbp + LOC_L], rax
    mov     rax, [rbp + LOC_TW]
    mov     [rbp + LOC_W], rax
    mov     rax, [rbp + LOC_TC]
    mov     [rbp + LOC_C], rax
    lea     rsi, [rip + total_name]
    call    emit_line

.finish:
    mov     rax, r14
    add     rsp, BUFSZ + 192
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

// ------------------------------------------------------------------ helpers

// count_fd: count lines/words/bytes of descriptor rbx.
//   returns r8 = lines, r9 = words, r10 = bytes; sets r14 on a read error.
//   The kernel preserves r8..r12 across the read syscall, so the running counts
//   and the in-word flag (r12) survive from block to block; r12 is saved/restored
//   so the caller's show mask is untouched.
count_fd:
    push    r12
    xor     r8, r8              // lines
    xor     r9, r9              // words
    xor     r10, r10            // bytes
    xor     r12, r12            // in-word flag
.cf_read:
    mov     rdi, rbx
    mov     rsi, r15
    mov     rdx, BUFSZ
    call    uolt_read
    test    rax, rax
    jz      .cf_done
    js      .cf_err
    add     r10, rax            // bytes += got
    xor     rcx, rcx            // i = 0
.cf_scan:
    cmp     rcx, rax
    jae     .cf_read
    movzx   edx, byte ptr [r15 + rcx]
    cmp     dl, 0x0a            // newline -> a line
    jne     1f
    inc     r8
1:
    cmp     dl, 0x20            // <blank>? space ...
    je      .cf_ws
    mov     edi, edx           // ... or 0x09..0x0d (tab, nl, vt, ff, cr)
    sub     edi, 9
    cmp     edi, 4
    jbe     .cf_ws
    test    r12, r12           // non-blank: start of a word?
    jnz     2f
    inc     r9
    mov     r12, 1
2:
    inc     rcx
    jmp     .cf_scan
.cf_ws:
    xor     r12, r12           // blank ends the current word
    inc     rcx
    jmp     .cf_scan
.cf_err:
    mov     r14, 1
.cf_done:
    pop     r12
    ret

// emit_line(name in rsi, or 0): print the enabled counts (from LOC_L/W/C per the
// r12 mask) separated by single spaces, then " name", then a newline.
emit_line:
    push    rbx
    mov     rbx, rsi            // name (preserved across the put_* calls)
    mov     byte ptr [rbp + LOC_FF], 1
    test    r12b, 1
    jz      1f
    call    sep_if_needed
    mov     rax, [rbp + LOC_L]
    call    put_uint
1:
    test    r12b, 2
    jz      2f
    call    sep_if_needed
    mov     rax, [rbp + LOC_W]
    call    put_uint
2:
    test    r12b, 8             // -m characters (before the byte column, GNU order)
    jz      5f
    call    sep_if_needed
    mov     rax, [rbp + LOC_C]  // C locale: characters == bytes
    call    put_uint
5:
    test    r12b, 4
    jz      3f
    call    sep_if_needed
    mov     rax, [rbp + LOC_C]
    call    put_uint
3:
    test    rbx, rbx
    jz      4f
    mov     al, ' '
    call    put_char
    mov     rsi, rbx
    call    put_str
4:
    mov     al, 0x0a
    call    put_char
    pop     rbx
    ret

// sep_if_needed: emit a single space before every field except the first.
sep_if_needed:
    cmp     byte ptr [rbp + LOC_FF], 0
    je      1f
    mov     byte ptr [rbp + LOC_FF], 0
    ret
1:
    mov     al, ' '
    // fall through to put_char (tail)
// put_char(al): write one byte to stdout.
put_char:
    mov     [rbp + LOC_CH], al
    mov     rdi, STDOUT
    lea     rsi, [rbp + LOC_CH]
    mov     rdx, 1
    jmp     uolt_write

// put_str(rsi = ASCIZ): write the string to stdout.
put_str:
    mov     rdi, rsi
    call    uolt_strlen         // rax = len; rsi preserved
    mov     rdx, rax
    mov     rdi, STDOUT
    jmp     uolt_write

// put_uint(rax = value): write the unsigned decimal value to stdout.
put_uint:
    lea     rdi, [rbp + LOC_NUM + 20]   // one past the end of the scratch
    test    rax, rax
    jnz     1f
    dec     rdi                         // value 0 -> "0"
    mov     byte ptr [rdi], '0'
    jmp     2f
1:
    mov     r11, rax                    // working value (no syscall until the write)
    mov     rcx, 10
.pu_loop:
    test    r11, r11
    jz      2f
    mov     rax, r11
    xor     rdx, rdx
    div     rcx                         // rax = q, rdx = digit
    add     dl, '0'
    dec     rdi
    mov     [rdi], dl
    mov     r11, rax
    jmp     .pu_loop
2:
    lea     rdx, [rbp + LOC_NUM + 20]
    sub     rdx, rdi                     // length
    mov     rsi, rdi
    mov     rdi, STDOUT
    jmp     uolt_write

// err_puts(rdi = ASCIZ) -> stderr; length via strlen (no magic numbers).
err_puts:
    mov     r8, rdi
    call    uolt_strlen
    mov     rdx, rax
    mov     rsi, r8
    mov     rdi, STDERR
    jmp     uolt_write

total_name: .asciz  "total"
err_pre:    .asciz  "uolt-wc: "
err_suf:    .asciz  ": cannot open\n"
