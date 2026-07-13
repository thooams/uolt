// src/yes/yes.S - uolt-yes: the POSIX `yes` utility.
//
// Repeatedly writes a line to stdout until the write fails (normally when the
// reader closes the pipe: the process is terminated by SIGPIPE, or -EPIPE is
// returned and it exits 1). The line is the operands joined by single spaces, or
// "y" when there are none, always followed by a newline.
//
// Naively writing one line per syscall makes `yes` slow; the whole point of the
// tool is throughput. So the line is replicated to fill a 64 KB stack buffer
// (no heap, Principle IV) and that buffer is written whole on each iteration,
// which keeps pace with the system tool. If the operands are so long that a
// single line exceeds 64 KB, it falls back to emitting the line piecewise from
// the original argv each iteration (rare).
//
// Called as uolt_main(argc in rdi, argv in rsi) by the per-OS entry shim.
//
// uolt_main register roles (callee-saved):
//   r12 = argument count, later the buffer fill length
//   r13 = &argv[1], later the running offset/copied length
//   r14 = line length L
//   r15 = base of the 64 KB stack buffer
//   rbx = scratch (loop index)

#include "uolt.inc"

.set STDOUT, 1
.set BUFSZ,  65536

.text
.globl uolt_main
uolt_main:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, BUFSZ
    mov     r15, rsp

    mov     r12, rdi
    dec     r12                 // argument count (argc - 1)
    lea     r13, [rsi + 8]      // &argv[1]

    test    r12, r12
    jnz     .have_args
    // No operands: the line is "y\n".
    mov     byte ptr [r15], 'y'
    mov     byte ptr [r15 + 1], 0x0a
    mov     r14, 2
    jmp     .batch

.have_args:
    // L = sum(strlen(arg)) + (spaces between + trailing newline) = sum + count.
    xor     rbx, rbx            // sum of lengths
    xor     rcx, rcx            // i
.sum_loop:
    cmp     rcx, r12
    jae     .sum_done
    mov     rdi, [r13 + rcx*8]
    call    uolt_strlen         // rax = len; preserves rbx, rcx
    add     rbx, rax
    inc     rcx
    jmp     .sum_loop
.sum_done:
    add     rbx, r12
    mov     r14, rbx            // L
    cmp     r14, BUFSZ
    ja      .fallback           // one line does not fit -> piecewise path

    // Build one copy of the line at the buffer start.
    xor     r9, r9              // pos
    xor     rbx, rbx            // i
.build:
    cmp     rbx, r12
    jae     .build_nl
    test    rbx, rbx
    jz      .no_space
    mov     byte ptr [r15 + r9], ' '
    inc     r9
.no_space:
    mov     rdi, [r13 + rbx*8]
    call    uolt_strlen         // rax = len; preserves rbx, r9
    mov     rsi, [r13 + rbx*8]  // src
    lea     rdi, [r15 + r9]     // dst
    mov     rcx, rax
    add     r9, rax             // pos += len (before rep clobbers rcx)
    rep     movsb
    inc     rbx
    jmp     .build
.build_nl:
    mov     byte ptr [r15 + r9], 0x0a   // r9 now equals L

.batch:
    // fill = floor(BUFSZ / L) * L : whole copies only.
    mov     rax, BUFSZ
    xor     rdx, rdx
    div     r14
    mul     r14
    mov     r12, rax            // fill
    // Replicate the first copy to fill the buffer (doubling copies).
    mov     r13, r14            // copied = L
.rep_fill:
    cmp     r13, r12
    jae     .rep_done
    mov     rcx, r13            // chunk = min(copied, fill - copied)
    mov     rax, r12
    sub     rax, r13
    cmp     rcx, rax
    jbe     1f
    mov     rcx, rax
1:
    mov     rsi, r15
    lea     rdi, [r15 + r13]
    add     r13, rcx            // copied += chunk (before rep clobbers rcx)
    rep     movsb
    jmp     .rep_fill
.rep_done:

    // Write the full buffer forever; drain short writes to keep line alignment.
.wloop:
    xor     r13, r13            // offset
.wdrain:
    cmp     r13, r12
    jae     .wloop
    mov     rdi, STDOUT
    lea     rsi, [r15 + r13]
    mov     rdx, r12
    sub     rdx, r13
    call    uolt_write
    test    rax, rax
    jle     .wexit              // <= 0: closed / error
    add     r13, rax
    jmp     .wdrain

// Piecewise path for a line longer than the buffer: emit args + spaces + newline
// straight from argv on every iteration.
.fallback:
.fb_loop:
    xor     rbx, rbx
.fb_arg:
    cmp     rbx, r12
    jae     .fb_nl
    test    rbx, rbx
    jz      .fb_nosp
    mov     byte ptr [r15], ' '
    mov     rdi, STDOUT
    mov     rsi, r15
    mov     rdx, 1
    call    uolt_write
    test    rax, rax
    jle     .wexit
.fb_nosp:
    mov     rdi, [r13 + rbx*8]
    call    uolt_strlen
    mov     rdx, rax
    mov     rsi, [r13 + rbx*8]
    mov     rdi, STDOUT
    call    uolt_write
    test    rax, rax
    jle     .wexit
    inc     rbx
    jmp     .fb_arg
.fb_nl:
    mov     byte ptr [r15], 0x0a
    mov     rdi, STDOUT
    mov     rsi, r15
    mov     rdx, 1
    call    uolt_write
    test    rax, rax
    jle     .wexit
    jmp     .fb_loop

.wexit:
    mov     eax, 1              // write failed (pipe closed) -> exit 1
    add     rsp, BUFSZ
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret
