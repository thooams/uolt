// src/dirname/dirname.S - uolt-dirname: the POSIX `dirname` utility.
//
// dirname string: prints the directory part of `string` (everything up to, but
// not including, the last path component), with a trailing newline. Following
// the POSIX algorithm: trailing '/' are stripped; a string with no '/' left
// yields "."; the separating '/' (and any repeats) before the last component are
// removed, and if nothing remains the result is "/". Like basename this is pure
// string work on the argv operand - no files, no buffer (Principle IV).
//
// Called as uolt_main(argc in rdi, argv in rsi) by the per-OS entry shim.
//
// Register roles:
//   r12 = the string operand
//   r8  = end index after stripping trailing slashes
//   r9  = working index (last-slash search, then dir length)

#include "uolt.inc"

.set STDOUT, 1
.set STDERR, 2

.text
.globl uolt_main
uolt_main:
    push    r12

    cmp     rdi, 2
    jl      .missing
    mov     r12, [rsi + 8]      // string (extra operands ignored)

    mov     rdi, r12
    call    uolt_strlen
    test    rax, rax
    jz      .dot                // empty string -> "."

    mov     r8, rax             // e = len
.strip:
    test    r8, r8
    jz      .root               // string was all slashes -> "/"
    cmp     byte ptr [r12 + r8 - 1], '/'
    jne     .stripped
    dec     r8
    jmp     .strip
.stripped:
    mov     r9, r8              // find the last '/' in s[0, e)
.findp:
    test    r9, r9
    jz      .dot                // no '/' -> "."
    cmp     byte ptr [r12 + r9 - 1], '/'
    je      .stripd
    dec     r9
    jmp     .findp
.stripd:
    // r9 points just past the last '/'. Strip that separator and any repeats;
    // the remainder [0, r9) is the directory (or "/" if it strips to nothing).
    test    r9, r9
    jz      .root
    cmp     byte ptr [r12 + r9 - 1], '/'
    jne     .emit_dir
    dec     r9
    jmp     .stripd
.emit_dir:
    mov     rdi, STDOUT
    lea     rsi, [r12]
    mov     rdx, r9             // directory length
    call    uolt_write
    jmp     .emit_nl
.dot:
    mov     rdi, STDOUT
    lea     rsi, [rip + dot_char]
    mov     rdx, 1
    call    uolt_write
    jmp     .emit_nl
.root:
    mov     rdi, STDOUT
    lea     rsi, [rip + slash]
    mov     rdx, 1
    call    uolt_write
.emit_nl:
    mov     rdi, STDOUT
    lea     rsi, [rip + nl_char]
    mov     rdx, 1
    call    uolt_write
    xor     eax, eax
    jmp     .ret

.missing:
    lea     rdi, [rip + err_missing]
    call    err_puts
    mov     eax, 1
.ret:
    pop     r12
    ret

// err_puts(rdi = ASCIZ) -> stderr; length via strlen (no magic numbers).
err_puts:
    mov     r8, rdi
    call    uolt_strlen
    mov     rdx, rax
    mov     rsi, r8
    mov     rdi, STDERR
    jmp     uolt_write

dot_char:    .byte  '.'
slash:       .byte  '/'
nl_char:     .byte  0x0a
err_missing: .asciz "uolt-dirname: missing operand\n"
