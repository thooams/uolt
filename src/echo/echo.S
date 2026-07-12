// src/echo/echo.S - uolt-echo: the POSIX `echo` utility.
//
// Writes its arguments to stdout, separated by single spaces, followed by a
// newline. A leading "-n" suppresses the trailing newline (BSD / common
// behavior; no GNU "-e" escape processing - POSIX, not GNU, Principle VIII).
//
// Called as uolt_main(argc in rdi, argv in rsi) by the per-OS entry shim.
// No heap (Principle IV): output is emitted with one write per piece (arg,
// separator, newline). Coalescing into a single writev is a future, measured
// optimization (Principle VII), not done prematurely here.
//
// Register roles across the loop (all callee-saved, so they survive the syscalls
// made by uolt_write / uolt_strlen):
//   r12 = remaining argument count
//   r13 = pointer to the current argv entry
//   r14 = suppress-newline flag (0 = print newline, 1 = -n given)
//   r15 = separator-needed flag (0 before first arg, 1 afterwards)
//   rbx = scratch pointer to the current argument string

#include "uolt.inc"

.set STDOUT, 1

.text
.globl uolt_main
uolt_main:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    mov     r12, rdi            // argc
    mov     r13, rsi            // argv
    add     r13, 8              // skip argv[0] (program name) -> &argv[1]
    dec     r12                 // count of user arguments
    xor     r14, r14            // print newline by default
    xor     r15, r15            // no separator before the first argument

    // Recognize a single leading "-n".
    test    r12, r12
    jz      .emit_end
    mov     rbx, [r13]          // argv[1]
    cmp     byte ptr [rbx], '-'
    jne     .loop
    cmp     byte ptr [rbx + 1], 'n'
    jne     .loop
    cmp     byte ptr [rbx + 2], 0
    jne     .loop
    mov     r14, 1              // -n: suppress trailing newline
    add     r13, 8
    dec     r12

.loop:
    test    r12, r12
    jz      .emit_end

    test    r15, r15            // need a space separator?
    jz      .no_sep
    mov     rdi, STDOUT
    lea     rsi, [rip + sp_char]
    mov     rdx, 1
    call    uolt_write
.no_sep:
    mov     r15, 1

    mov     rbx, [r13]          // current argument string
    mov     rdi, rbx
    call    uolt_strlen         // rax = length
    mov     rdx, rax
    mov     rsi, rbx
    mov     rdi, STDOUT
    call    uolt_write

    add     r13, 8
    dec     r12
    jmp     .loop

.emit_end:
    test    r14, r14            // -n given? then no newline
    jnz     .done
    mov     rdi, STDOUT
    lea     rsi, [rip + nl_char]
    mov     rdx, 1
    call    uolt_write
.done:
    xor     rax, rax            // exit status 0
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

// Single-byte constants kept in the text segment (the Linux link script folds
// rodata into .text; macOS keeps them in __TEXT). Reached only via lea, never
// executed.
sp_char: .byte 0x20             // ' '
nl_char: .byte 0x0a             // '\n'
