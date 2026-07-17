// src/cat/cat.S - uolt-cat: the POSIX `cat` utility.
//
// Concatenates its file operands to stdout, in order. With no operands (or the
// operand "-") it copies standard input. Data is moved in fixed-size blocks
// through a single stack buffer (no heap, Principle IV): read a chunk, write it
// out in full, repeat until EOF. Bytes are copied verbatim - no line handling,
// no numbering, no escaping (POSIX, not GNU, Principle VIII).
//
// POSIX `cat` has one option, -u (unbuffered); since UOLT issues direct read/
// write syscalls with no stdio buffering, output is already unbuffered, so -u is
// accepted and ignored. Any other operand is treated as a filename.
//
// Called as uolt_main(argc in rdi, argv in rsi) by the per-OS entry shim.
// If a file cannot be opened, a diagnostic goes to stderr, the exit status is
// set to 1, and the remaining operands are still processed (POSIX behavior).
//
// Register roles (all callee-saved, so they survive the read/write/open/close
// syscalls made along the way):
//   r12 = remaining operand count
//   r13 = pointer to the current argv entry
//   r14 = accumulated exit status (0 ok, 1 if any file failed / read errored)
//   r15 = base of the stack copy buffer
//   rbx = scratch: current operand string, then the open file descriptor

#include "uolt.inc"

.set STDIN,    0
.set STDOUT,   1
.set STDERR,   2
.set O_RDONLY, 0                // read-only open flag (0 on Linux and macOS)
.set BUFSZ,    65536            // copy block size; bigger buffer = fewer syscalls

.text
.globl uolt_main
uolt_main:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, BUFSZ          // stack copy buffer (Principle IV: no heap)
    mov     r15, rsp            // buffer base

    mov     r12, rdi            // argc
    mov     r13, rsi            // argv
    xor     r14, r14            // exit status 0
    add     r13, 8              // skip argv[0] (program name) -> &argv[1]
    dec     r12                 // count of operands

    test    r12, r12
    jz      .stdin_only         // no operands -> copy stdin

.loop:
    test    r12, r12
    jz      .finish
    mov     rbx, [r13]          // current operand string

    cmp     byte ptr [rbx], '-'
    jne     .open_file          // not dash-led -> a filename
    cmp     byte ptr [rbx + 1], 0
    je      .stdin_operand      // exactly "-" -> stdin operand
    cmp     byte ptr [rbx + 1], 'u'
    jne     .open_file          // "-x": not our option, treat as filename
    cmp     byte ptr [rbx + 2], 0
    jne     .open_file
    // "-u": the sole POSIX option; already unbuffered, so ignore it.
    add     r13, 8
    dec     r12
    jmp     .loop

.stdin_operand:
    mov     rbx, STDIN
    call    cat_fd
    jmp     .next

.open_file:
    mov     rdi, rbx            // path
    mov     rsi, O_RDONLY
    xor     rdx, rdx            // mode unused for O_RDONLY
    call    uolt_open
    test    rax, rax
    js      .open_error        // negative -> could not open
    mov     rbx, rax            // fd
    call    cat_fd
    mov     rdi, rbx            // close(fd)
    call    uolt_close
    jmp     .next

.open_error:
    mov     r14, 1             // failure, but keep going with remaining operands
    lea     rdi, [rip + err_pre]    // "uolt-cat: "
    call    err_puts
    mov     rdi, rbx                // the offending filename (NUL-terminated argv)
    call    err_puts
    lea     rdi, [rip + err_suf]    // ": cannot open\n"
    call    err_puts

.next:
    add     r13, 8
    dec     r12
    jmp     .loop

.stdin_only:
    mov     rbx, STDIN
    call    cat_fd

.finish:
    mov     rax, r14           // exit status
    add     rsp, BUFSZ
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

// cat_fd - copy everything from an open descriptor to stdout.
//   input:  rbx = file descriptor, r15 = buffer base
//   output: r14 set to 1 on a read/write error
//   clobbers rax, rcx, rdx, rsi, rdi, r8, r9, r11 (all caller-saved); rbx and
//   r15 are preserved, and the syscalls preserve r8/r9 (kernel touches only
//   rax/rcx/r11), so the write drain below is safe across calls.
cat_fd:
1:
    mov     rdi, rbx            // read(fd, buf, BUFSZ)
    mov     rsi, r15
    mov     rdx, BUFSZ
    call    uolt_read
    test    rax, rax
    jz      3f                 // 0 -> EOF, done
    js      2f                 // < 0 -> read error
    // Drain the whole chunk to stdout (a single write may be short on a pipe).
    mov     r8, rax            // bytes remaining
    mov     r9, r15            // current position
4:
    mov     rdi, STDOUT
    mov     rsi, r9
    mov     rdx, r8
    call    uolt_write
    test    rax, rax
    js      2f                 // write error
    add     r9, rax
    sub     r8, rax
    jnz     4b                 // more of this chunk to write
    jmp     1b
2:
    mov     r14, 1             // read/write failure
3:
    ret

// err_puts - write a NUL-terminated string to stderr.
//   input:  rdi = pointer to an ASCIZ string
//   clobbers rax, rcx, rdx, rsi, rdi, r8, r11; length is measured with strlen
//   rather than baked in as a constant (Principle IX: no magic numbers).
err_puts:
    mov     r8, rdi            // r8 survives strlen (it touches only rax)
    call    uolt_strlen        // rdi=ptr -> rax=length
    mov     rdx, rax           // length
    mov     rsi, r8            // buffer
    mov     rdi, STDERR
    jmp     uolt_write         // tail call: return to err_puts's caller

// Diagnostic fragments for a failed open. Kept in the text segment (the Linux
// link script folds rodata into .text; macOS keeps them in __TEXT); reached only
// via lea, never executed.
err_pre: .asciz "uolt-cat: "
err_suf: .asciz ": cannot open\n"
