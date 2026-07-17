// src/basename/basename.S - uolt-basename: the POSIX `basename` utility.
//
// basename string [suffix]: prints the final path component of `string`, with a
// trailing newline. Trailing '/' are removed first; a string of only slashes
// becomes "/"; an empty string prints an empty line. If a `suffix` operand is
// given and the component ends with it - but is not equal to it - the suffix is
// removed. This is pure string work on the argv operands: no files are opened,
// no buffer is allocated (Principle IV); the result is written straight from the
// operand's own bytes.
//
// GNU's -a/-s/-z extensions are out of scope in v1 (POSIX form only).
//
// Called as uolt_main(argc in rdi, argv in rsi) by the per-OS entry shim.
//
// Register roles:
//   r12 = the string operand, r13 = the suffix operand (0 if none)
//   r8  = end index (past the last kept byte), r9 = component start index,
//   r10 = component length

#include "uolt.inc"

.set STDOUT, 1
.set STDERR, 2

.text
.globl uolt_main
uolt_main:
    push    r12
    push    r13

    cmp     rdi, 2
    jl      .missing            // need at least one operand
    mov     r12, [rsi + 8]      // string
    xor     r13, r13
    cmp     rdi, 3
    jl      1f
    mov     r13, [rsi + 16]     // suffix (extra operands ignored)
1:
    mov     rdi, r12            // len = strlen(string)
    call    uolt_strlen
    test    rax, rax
    jz      .emit_nl            // empty string -> empty line

    mov     r8, rax             // e = len
.strip:
    test    r8, r8
    jz      .all_slash
    cmp     byte ptr [r12 + r8 - 1], '/'
    jne     .stripped
    dec     r8                  // drop a trailing slash
    jmp     .strip
.all_slash:
    mov     rdi, STDOUT         // whole string was slashes -> "/"
    lea     rsi, [rip + slash]
    mov     rdx, 1
    call    uolt_write
    jmp     .emit_nl
.stripped:
    mov     r9, r8              // find the byte after the last '/'
.findb:
    test    r9, r9
    jz      .have_b
    cmp     byte ptr [r12 + r9 - 1], '/'
    je      .have_b
    dec     r9
    jmp     .findb
.have_b:
    mov     r10, r8             // component length = e - b
    sub     r10, r9

    test    r13, r13            // suffix given?
    jz      .emit
    mov     rdi, r13
    call    uolt_strlen         // rax = suffix length; r8/r9/r10/r12/r13 preserved
    test    rax, rax
    jz      .emit
    cmp     rax, r10
    jae     .emit               // suffix >= component (equal or longer) -> keep whole
    // Compare the component's tail with the suffix.
    mov     rsi, r12
    add     rsi, r8
    sub     rsi, rax            // s + e - suffixlen
    mov     rdi, r13
    mov     rcx, rax
.cmpl:
    test    rcx, rcx
    jz      .suffix_match
    mov     dl, [rsi]
    cmp     dl, [rdi]
    jne     .emit               // mismatch -> keep whole component
    inc     rsi
    inc     rdi
    dec     rcx
    jmp     .cmpl
.suffix_match:
    sub     r10, rax            // strip the suffix
.emit:
    mov     rdi, STDOUT         // write component [b, b+len)
    lea     rsi, [r12 + r9]
    mov     rdx, r10
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
    pop     r13
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

slash:       .byte  '/'
nl_char:     .byte  0x0a
err_missing: .asciz "uolt-basename: missing operand\n"
