// src/seq/seq.S - the `seq` utility (integers).
//
// seq [first [incr]] last: print the integer sequence from first to last,
// stepping by incr, one number per line. Defaults: first = 1, incr = 1. A
// negative incr counts down. Non-integer (floating) operands and format options
// (-w, -f, -s) are out of scope in v1.
//
// Numbers are formatted into a small stack buffer (no heap, Principle IV) and
// written one line at a time. An invalid operand, a zero increment, or the wrong
// operand count is an error (stderr diagnostic, exit 1).
//
// Called as uolt_main(argc in rdi, argv in rsi) by the per-OS entry shim.
//
// Register roles (callee-saved): r12 = first, r13 = incr, r14 = last, r15 = the
//   running value. Stack: a 32-byte number buffer.

#include "uolt.inc"

.set STDOUT, 1
.set STDERR, 2

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
    sub     rsp, 32                     // number buffer at [rbp-72 .. rbp-40)

    mov     rbx, rsi                    // argv
    mov     r10, rdi
    dec     r10                         // operand count

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
    mov     rdi, [rbx + 8]
    call    parse_int
    jc      .bad
    mov     r14, rax                    // last
    jmp     .ready
.two:
    mov     rdi, [rbx + 8]
    call    parse_int
    jc      .bad
    mov     r12, rax                    // first
    mov     rdi, [rbx + 16]
    call    parse_int
    jc      .bad
    mov     r14, rax                    // last
    jmp     .ready
.three:
    mov     rdi, [rbx + 8]
    call    parse_int
    jc      .bad
    mov     r12, rax
    mov     rdi, [rbx + 16]
    call    parse_int
    jc      .bad
    mov     r13, rax                    // incr
    mov     rdi, [rbx + 24]
    call    parse_int
    jc      .bad
    mov     r14, rax                    // last
.ready:
    test    r13, r13
    jz      .bad                        // zero increment
    mov     r15, r12                    // i = first

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
    mov     rax, r15
    call    emit_num
    add     r15, r13
    jmp     .loop
.done:
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
    add     rsp, 32
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

// emit_num(rax = signed value): format "value\n" into the stack buffer and write
// it. Uses the 32-byte buffer at [rbp-72]; clobbers caller-saved registers only.
emit_num:
    lea     rdi, [rbp - 41]             // last buffer byte
    mov     byte ptr [rdi], 0x0a        // trailing newline
    xor     r9, r9                      // negative flag
    test    rax, rax
    jns     1f
    mov     r9, 1
    neg     rax
1:
    mov     rcx, 10
2:
    xor     rdx, rdx
    div     rcx                         // rax/=10, rdx=digit
    add     dl, '0'
    dec     rdi
    mov     [rdi], dl
    test    rax, rax
    jnz     2b
    test    r9, r9
    jz      3f
    dec     rdi
    mov     byte ptr [rdi], '-'
3:
    lea     rdx, [rbp - 40]             // one past the newline
    sub     rdx, rdi                    // length
    mov     rsi, rdi
    mov     rdi, STDOUT
    jmp     uolt_write

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

err_usage: .asciz "uolt-seq: usage: seq [first [incr]] last\n"
err_bad:   .asciz "uolt-seq: invalid integer argument\n"
