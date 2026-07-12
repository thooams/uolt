// src/head/head.S - uolt-head: the POSIX `head` utility.
//
// Writes the first N lines (default 10) of each file operand to stdout. With no
// operand, or the operand "-", it reads standard input. When more than one
// operand is given, each is preceded by a "==> name <==" header, and a blank
// line separates consecutive sections (the format GNU and BSD head share).
//
// Only POSIX option -n is recognized (as "-n number" or "-nnumber"); "--" ends
// option processing. A line is a run of bytes ending in '\n'; a final line with
// no trailing newline still counts. Data is streamed through one 64 KB stack
// buffer (no heap, Principle IV): each read block is scanned for the cut point
// (the Nth newline) and the consumed prefix is drained to stdout in full.
//
// Called as uolt_main(argc in rdi, argv in rsi) by the per-OS entry shim.
// On a file that cannot be opened, a diagnostic goes to stderr, the exit status
// becomes 1, and the remaining operands are still processed (no header is
// printed for a file that failed to open).
//
// Register roles in uolt_main (all callee-saved, so they survive the syscalls):
//   r12 = line count N (parsed from -n, default 10)
//   r13 = pointer to the current argv entry
//   r14 = accumulated exit status (0 ok, 1 on any open/read/write error)
//   r15 = base of the 64 KB stack copy buffer
//   rbx = scratch: current operand string, then the open file descriptor
// Stack locals (rbp-relative, below the saved registers):
//   [rbp-48] = remaining operand count
//   [rbp-56] = header flag (1 = print "==> name <==" headers: >1 operand)
//   [rbp-64] = first-output flag (1 until the first header is emitted)

#include "uolt.inc"

.set STDIN,    0
.set STDOUT,   1
.set STDERR,   2
.set O_RDONLY, 0
.set BUFSZ,    65536
.set DEFLINES, 10               // POSIX default: first 10 lines

.set LOC_REM,   -48
.set LOC_HDR,   -56
.set LOC_FIRST, -64

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
    sub     rsp, BUFSZ + 64     // 64 KB buffer + room for the stack locals
    mov     r15, rsp            // buffer base
    xor     r14, r14            // exit status 0

    // --- Option parsing: set N (r12), advance r13 to the first operand,
    //     leave the operand count in rcx. ---
    mov     r12, DEFLINES
    mov     r13, rsi            // argv
    add     r13, 8              // &argv[1]
    mov     rcx, rdi
    dec     rcx                 // candidate operand count (argc - 1)

.opt:
    test    rcx, rcx
    jz      .opt_done
    mov     rbx, [r13]
    cmp     byte ptr [rbx], '-'
    jne     .opt_done           // first non-dash token -> operands begin
    cmp     byte ptr [rbx + 1], 0
    je      .opt_done           // "-" is the stdin operand, not an option
    cmp     byte ptr [rbx + 1], '-'
    jne     .chk_n
    cmp     byte ptr [rbx + 2], 0
    jne     .chk_n              // "--foo": not ours; let it be an operand
    add     r13, 8              // "--": consume, end of options
    dec     rcx
    jmp     .opt_done
.chk_n:
    cmp     byte ptr [rbx + 1], 'n'
    jne     .opt_done           // unknown option -> treat rest as operands
    cmp     byte ptr [rbx + 2], 0
    jne     .n_joined
    // "-n" with the number in the next argument.
    add     r13, 8
    dec     rcx
    test    rcx, rcx
    jz      .n_missing
    mov     rdi, [r13]
    call    parse_uint          // preserves rcx
    mov     r12, rax
    add     r13, 8
    dec     rcx
    jmp     .opt
.n_joined:
    lea     rdi, [rbx + 2]      // "-nNUMBER"
    call    parse_uint
    mov     r12, rax
    add     r13, 8
    dec     rcx
    jmp     .opt

.n_missing:
    mov     r14, 1
    lea     rdi, [rip + err_narg]
    call    err_puts
    jmp     .finish

.opt_done:
    mov     [rbp + LOC_REM], rcx

    // No operands -> read stdin once, no header.
    test    rcx, rcx
    jnz     .have_ops
    mov     rbx, STDIN
    mov     rdi, r12
    call    head_fd
    jmp     .finish

.have_ops:
    // Headers only when more than one operand.
    mov     qword ptr [rbp + LOC_HDR], 0
    cmp     rcx, 1
    jbe     1f
    mov     qword ptr [rbp + LOC_HDR], 1
1:
    mov     qword ptr [rbp + LOC_FIRST], 1

.ploop:
    cmp     qword ptr [rbp + LOC_REM], 0
    je      .finish
    mov     rbx, [r13]          // current operand

    cmp     byte ptr [rbx], '-'
    jne     .pf_open
    cmp     byte ptr [rbx + 1], 0
    jne     .pf_open

    // stdin operand ("-")
    cmp     qword ptr [rbp + LOC_HDR], 0
    je      2f
    lea     rsi, [rip + stdin_name]
    call    print_header
2:
    mov     rbx, STDIN
    mov     rdi, r12
    call    head_fd
    jmp     .pnext

.pf_open:
    mov     rdi, rbx            // path
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    call    uolt_open
    test    rax, rax
    js      .pf_err
    mov     rbx, rax            // fd
    cmp     qword ptr [rbp + LOC_HDR], 0
    je      3f
    mov     rsi, [r13]          // header name = filename (print_header preserves rbx)
    call    print_header
3:
    mov     rdi, r12            // line count N
    call    head_fd             // uses rbx = fd
    mov     rdi, rbx
    call    uolt_close
    jmp     .pnext

.pf_err:
    mov     r14, 1             // failure; no header for a file that never opened
    lea     rdi, [rip + err_pre]
    call    err_puts
    mov     rdi, [r13]
    call    err_puts
    lea     rdi, [rip + err_suf]
    call    err_puts

.pnext:
    add     r13, 8
    dec     qword ptr [rbp + LOC_REM]
    jmp     .ploop

.finish:
    mov     rax, r14
    add     rsp, BUFSZ + 64
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

// head_fd - copy the first r10 lines of an open descriptor to stdout.
//   input:  rbx = file descriptor, rdi = line count N, r15 = buffer base
//   output: r14 set to 1 on a read/write error
//   r10 holds the remaining line countdown; the kernel preserves r8/r9/r10
//   across syscalls, so the buffer scan below survives the read/write calls.
head_fd:
    mov     r10, rdi            // remaining lines
    test    r10, r10
    jz      9f                 // -n 0: emit nothing
1:
    mov     rdi, rbx            // read(fd, buf, BUFSZ)
    mov     rsi, r15
    mov     rdx, BUFSZ
    call    uolt_read
    test    rax, rax
    jz      9f                 // EOF
    js      8f                 // read error
    // Scan [r15, r15+rax) for the r10-th newline.
    mov     r8, r15            // cursor
    lea     r9, [r15 + rax]    // end of valid data
2:
    cmp     r8, r9
    je      .whole             // block holds fewer than r10 lines: emit it all
    cmp     byte ptr [r8], 0x0a
    jne     3f
    inc     r8                 // include the newline in this line
    dec     r10
    jz      .cut               // reached N lines: stop right after this newline
    jmp     2b
3:
    inc     r8
    jmp     2b
.whole:
    mov     rsi, r15
    mov     rdx, rax           // full block length (rax untouched since read)
    call    emit
    jmp     1b                 // read the next block
.cut:
    mov     rsi, r15
    mov     rdx, r8
    sub     rdx, r15           // bytes up to and including the Nth newline
    call    emit
    jmp     9f
8:
    mov     r14, 1             // read error
9:
    ret

// emit - drain rdx bytes at rsi to stdout, tolerating short writes.
//   preserves rbx, r10, r12-r15; uses r8/r9 as its own cursor/remaining (safe:
//   head_fd re-scans from scratch after a whole-block emit).
emit:
    mov     r8, rsi            // cursor
    mov     r9, rdx            // remaining
1:
    test    r9, r9
    jz      2f
    mov     rdi, STDOUT
    mov     rsi, r8
    mov     rdx, r9
    call    uolt_write
    test    rax, rax
    js      3f                 // write error
    add     r8, rax
    sub     r9, rax
    jmp     1b
3:
    mov     r14, 1
2:
    ret

// print_header - write "==> name <==\n" (with a leading blank line except the
// first time) to stdout.
//   input:  rsi = name (ASCIZ)
//   preserves rbx (holds the caller's fd) and r12-r15.
print_header:
    push    rbx                // save caller's fd; reuse rbx as a stable name ptr
    mov     rbx, rsi
    cmp     qword ptr [rbp + LOC_FIRST], 0
    jne     1f
    mov     rdi, STDOUT        // blank-line separator between sections
    lea     rsi, [rip + nl_char]
    mov     rdx, 1
    call    uolt_write
1:
    mov     qword ptr [rbp + LOC_FIRST], 0
    mov     rdi, STDOUT        // "==> "
    lea     rsi, [rip + hdr_pre]
    mov     rdx, 4
    call    uolt_write
    mov     rdi, rbx           // the name
    call    uolt_strlen
    mov     rdx, rax
    mov     rsi, rbx
    mov     rdi, STDOUT
    call    uolt_write
    mov     rdi, STDOUT        // " <==\n"
    lea     rsi, [rip + hdr_suf]
    mov     rdx, 5
    call    uolt_write
    pop     rbx
    ret

// parse_uint - decimal string -> unsigned integer.
//   input:  rdi = ASCIZ digit string; stops at the first non-digit (lenient)
//   output: rax = value; clobbers rax, rdx, rdi (preserves rcx for the caller)
parse_uint:
    xor     rax, rax
1:
    movzx   rdx, byte ptr [rdi]
    sub     rdx, '0'
    cmp     rdx, 9
    ja      2f                 // non-digit (incl NUL) -> done
    imul    rax, rax, 10
    add     rax, rdx
    inc     rdi
    jmp     1b
2:
    ret

// err_puts - write a NUL-terminated string to stderr (length via strlen, so no
// magic-number lengths, Principle IX). Preserves r12-r15.
err_puts:
    mov     r8, rdi            // r8 survives strlen (it touches only rax)
    call    uolt_strlen
    mov     rdx, rax
    mov     rsi, r8
    mov     rdi, STDERR
    jmp     uolt_write         // tail call

// Read-only text kept in the code segment (the Linux link script folds rodata
// into .text; macOS keeps it in __TEXT). Reached only via lea, never executed.
hdr_pre:    .ascii  "==> "
hdr_suf:    .ascii  " <==\n"
nl_char:    .byte   0x0a
stdin_name: .asciz  "standard input"
err_pre:    .asciz  "uolt-head: "
err_suf:    .asciz  ": cannot open\n"
err_narg:   .asciz  "uolt-head: option requires an argument -- n\n"
