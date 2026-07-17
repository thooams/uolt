// src/seq/seq.S - the `seq` utility (integers).
//
// seq [-s STRING] [-w] [first [incr]] last: print the integer sequence from
// first to last, stepping by incr. Defaults: first = 1, incr = 1, one number
// per line. -s sets the separator placed between numbers (a newline still
// terminates the output). -w pads every number with leading zeros to the width
// of the widest term. A negative incr counts down. Non-integer (floating)
// operands and -f are out of scope in v1.
//
// Numbers are formatted into a small stack buffer (no heap, Principle IV) and
// written one at a time. An invalid operand, a zero increment, or the wrong
// operand count is an error (stderr diagnostic, exit 1).
//
// Called as uolt_main(argc in rdi, argv in rsi) by the per-OS entry shim.
//
// Register roles (callee-saved): r12 = first, r13 = incr, r14 = last, r15 = the
//   running value. Number buffer at [rbp-72 .. rbp-40); stack locals below it.

#include "uolt.inc"

.set STDOUT, 1
.set STDERR, 2

.set LOC_SEP,    -80         // separator pointer (default = newline)
.set LOC_SEPLEN, -88         // separator length
.set LOC_WIDTH,  -96         // pad width (0 = no -w)
.set LOC_FIRST,  -104        // 1 until the first number is emitted

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
    sub     rsp, 96

    lea     rbx, [rsi + 8]              // &argv[1] (first operand)
    mov     r10, rdi
    dec     r10                         // operand count

    lea     rax, [rip + nl]             // default separator = "\n"
    mov     [rbp + LOC_SEP], rax
    mov     qword ptr [rbp + LOC_SEPLEN], 1
    mov     qword ptr [rbp + LOC_WIDTH], 0

.opt:
    test    r10, r10
    jz      .parsed
    mov     rdi, [rbx]
    cmp     byte ptr [rdi], '-'
    jne     .parsed
    cmp     byte ptr [rdi + 1], 0
    je      .parsed                     // "-" alone is not an option
    movzx   eax, byte ptr [rdi + 1]
    cmp     al, 'w'
    je      .opt_w
    cmp     al, 's'
    je      .opt_s
    cmp     al, '-'
    je      .opt_ddash
    // A leading '-' before a digit is a negative operand, not an option.
    movzx   eax, byte ptr [rdi + 1]
    sub     al, '0'
    cmp     al, 9
    jbe     .parsed
    jmp     .usage
.opt_w:
    cmp     byte ptr [rdi + 2], 0
    jne     .usage
    mov     qword ptr [rbp + LOC_WIDTH], 1     // sentinel; real width set later
    add     rbx, 8
    dec     r10
    jmp     .opt
.opt_s:
    lea     rdi, [rdi + 2]              // "-sSEP" attached, or "-s" then next arg
    cmp     byte ptr [rdi], 0
    jne     .have_sep
    add     rbx, 8
    dec     r10
    jz      .usage
    mov     rdi, [rbx]
.have_sep:
    mov     [rbp + LOC_SEP], rdi
    call    uolt_strlen
    mov     [rbp + LOC_SEPLEN], rax
    add     rbx, 8
    dec     r10
    jmp     .opt
.opt_ddash:
    cmp     byte ptr [rdi + 2], 0
    jne     .usage
    add     rbx, 8
    dec     r10
.parsed:
    mov     r12, 1                      // first
    mov     r13, 1                      // incr
    cmp     r10, 1
    je      .one
    cmp     r10, 2
    je      .two
    cmp     r10, 3
    je      .three
    jmp     .usage
.one:
    mov     rdi, [rbx]
    call    parse_int
    jc      .bad
    mov     r14, rax
    jmp     .ready
.two:
    mov     rdi, [rbx]
    call    parse_int
    jc      .bad
    mov     r12, rax
    mov     rdi, [rbx + 8]
    call    parse_int
    jc      .bad
    mov     r14, rax
    jmp     .ready
.three:
    mov     rdi, [rbx]
    call    parse_int
    jc      .bad
    mov     r12, rax
    mov     rdi, [rbx + 8]
    call    parse_int
    jc      .bad
    mov     r13, rax
    mov     rdi, [rbx + 16]
    call    parse_int
    jc      .bad
    mov     r14, rax
.ready:
    test    r13, r13
    jz      .bad                        // zero increment

    // -w: pad width = max(fmt_len(first), fmt_len(last))
    cmp     qword ptr [rbp + LOC_WIDTH], 0
    je      .noW
    mov     rax, r12
    call    fmt_len
    mov     rbx, rax
    mov     rax, r14
    call    fmt_len
    cmp     rax, rbx
    jae     1f
    mov     rax, rbx
1:
    mov     [rbp + LOC_WIDTH], rax
.noW:
    mov     r15, r12                    // i = first
    mov     qword ptr [rbp + LOC_FIRST], 1

.loop:
    test    r13, r13
    js      .down
    cmp     r15, r14                    // ascending: stop when i > last
    jg      .done
    jmp     .emit
.down:
    cmp     r15, r14                    // descending: stop when i < last
    jl      .done
.emit:
    cmp     qword ptr [rbp + LOC_FIRST], 0
    jne     .noSEP
    mov     rdi, STDOUT                 // separator before every number but the first
    mov     rsi, [rbp + LOC_SEP]
    mov     rdx, [rbp + LOC_SEPLEN]
    call    uolt_write
.noSEP:
    mov     qword ptr [rbp + LOC_FIRST], 0
    mov     rax, r15
    call    put_num
    add     r15, r13
    jmp     .loop
.done:
    cmp     qword ptr [rbp + LOC_FIRST], 1
    je      .done0                      // empty sequence -> no trailing newline
    mov     byte ptr [rbp - 40], 0x0a
    mov     rdi, STDOUT
    lea     rsi, [rbp - 40]
    mov     rdx, 1
    call    uolt_write
.done0:
    xor     eax, eax
    jmp     .ret
.bad:
    lea     rdi, [rip + err_bad]
    call    err_puts
    mov     eax, 1
    jmp     .ret
.usage:
    lea     rdi, [rip + err_usage]
    call    err_puts
    mov     eax, 1
.ret:
    add     rsp, 96
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

// put_num(rax = signed value): format the value (zero-padded to LOC_WIDTH when
// set) with no trailing newline, and write it. Uses the buffer at [rbp-72).
put_num:
    lea     rdi, [rbp - 40]             // one past the buffer end
    xor     r9, r9                      // negative flag
    test    rax, rax
    jns     1f
    mov     r9, 1
    neg     rax
1:
    mov     rcx, 10
    xor     r11, r11                    // digit count
2:
    xor     rdx, rdx
    div     rcx
    add     dl, '0'
    dec     rdi
    mov     [rdi], dl
    inc     r11
    test    rax, rax
    jnz     2b
    // pad with leading zeros: current width = digits + sign
    mov     rax, [rbp + LOC_WIDTH]
    test    rax, rax
    jz      .pn_sign
    lea     rcx, [r11 + r9]
.pn_pad:
    cmp     rcx, rax
    jae     .pn_sign
    dec     rdi
    mov     byte ptr [rdi], '0'
    inc     rcx
    jmp     .pn_pad
.pn_sign:
    test    r9, r9
    jz      3f
    dec     rdi
    mov     byte ptr [rdi], '-'
3:
    lea     rdx, [rbp - 40]
    sub     rdx, rdi                    // length
    mov     rsi, rdi
    mov     rdi, STDOUT
    jmp     uolt_write

// fmt_len(rax = signed value) -> rax = printed length (digits + sign).
fmt_len:
    xor     r8, r8
    test    rax, rax
    jns     1f
    mov     r8, 1
    neg     rax
1:
    mov     rcx, 10
    xor     r11, r11
2:
    xor     rdx, rdx
    div     rcx
    inc     r11
    test    rax, rax
    jnz     2b
    lea     rax, [r11 + r8]
    ret

// parse_int(rdi = ASCIZ) -> rax = value; CF set on error (empty or non-digit).
// Accepts an optional leading '-'.
parse_int:
    xor     rax, rax
    xor     r8, r8                      // negative flag
    movzx   rcx, byte ptr [rdi]
    cmp     cl, '-'
    jne     1f
    mov     r8, 1
    inc     rdi
1:
    xor     r9, r9                      // digit-seen flag
.pi:
    movzx   rcx, byte ptr [rdi]
    test    cl, cl
    jz      .pi_done
    sub     cl, '0'
    cmp     cl, 9
    ja      .pi_err
    imul    rax, rax, 10
    movzx   rcx, cl
    add     rax, rcx
    mov     r9, 1
    inc     rdi
    jmp     .pi
.pi_done:
    test    r9, r9
    jz      .pi_err
    test    r8, r8
    jz      1f
    neg     rax
1:
    clc
    ret
.pi_err:
    stc
    ret

err_puts:
    mov     r10, rdi
    call    uolt_strlen
    mov     rdx, rax
    mov     rsi, r10
    mov     rdi, STDERR
    jmp     uolt_write

nl:        .asciz "\n"
err_usage: .asciz "uolt-seq: usage: seq [-s STRING] [-w] [first [incr]] last\n"
err_bad:   .asciz "uolt-seq: invalid integer argument\n"
