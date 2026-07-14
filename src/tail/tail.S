// src/tail/tail.S - uolt-tail: the POSIX `tail` utility.
//
// Writes the last N lines (default 10) of each file operand, or of standard
// input, to stdout. With "-n +N" it instead starts at line N and copies to the
// end. When more than one operand is given, each is preceded by a
// "==> name <==" header (the format shared by GNU and BSD), with a blank line
// between consecutive sections. Only POSIX option -n is recognized ("-n number",
// "-n +number", or the joined "-nnumber"/"-n+number"); "--" ends options. The
// GNU/BSD extensions -c (bytes) and -f (follow) are out of scope in v1.
//
// The hard part of `tail` is finding the *last* N lines without a heap
// (Principle IV). Two paths, chosen at run time:
//   * Seekable input (regular file): lseek to the end, then read fixed 64 KB
//     blocks backwards counting newlines until the Nth boundary is found; seek
//     there and copy forward to EOF. Cost is proportional to the output, not the
//     file size, so it keeps pace with the system tool on large files.
//   * Non-seekable input (pipe/stdin, lseek returns -ESPIPE): stream forward
//     into a sliding window that retains only the last 64 KB, then locate the
//     last N lines inside it. If those lines exceed 64 KB the window caps the
//     output at its last 64 KB (a documented no-heap limit).
//
// Called as uolt_main(argc in rdi, argv in rsi). A file that cannot be opened
// yields a stderr diagnostic (no header), sets the exit status to 1, and does
// not stop the remaining operands.
//
// uolt_main register roles (callee-saved; survive the syscalls):
//   r13 = pointer to the current argv entry
//   r14 = accumulated exit status
//   r15 = base of the stack window buffer (2 * BUFSZ bytes)
//   rbx = scratch: current operand string, then the open file descriptor
// Stack locals (rbp-relative):
//   [rbp-48]=remaining operand count  [rbp-56]=header flag  [rbp-64]=first flag
//   [rbp-72]=line count N             [rbp-80]=plus flag (-n +N)

#include "uolt.inc"

.set STDIN,    0
.set STDOUT,   1
.set STDERR,   2
.set O_RDONLY, 0
.set BUFSZ,    65536            // block size and sliding-window retention
.set DEFLINES, 10
.set SEEK_SET, 0
.set SEEK_END, 2

.set LOC_REM,   -48
.set LOC_HDR,   -56
.set LOC_FIRST, -64
.set LOC_N,     -72
.set LOC_PLUS,  -80
// Scratch slots for the backward scan (kept in memory because it spans lseek and
// read_exact calls, which clobber the caller-saved registers).
.set LOC_CNT,   -88             // newline count so far
.set LOC_FB,    -96             // firstbyte flag (skip one trailing newline)
.set LOC_CS,    -104            // current chunk size
.set LOC_BYTES, -112            // -c mode: count bytes instead of lines

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
    sub     rsp, 2*BUFSZ + 96   // sliding window (2*BUFSZ) + stack locals
    mov     r15, rsp            // buffer base
    xor     r14, r14            // exit status 0

    // --- Option parsing: N (default 10), plus flag; leave r13 at the first
    //     operand and the operand count in rcx. ---
    mov     qword ptr [rbp + LOC_N], DEFLINES
    mov     qword ptr [rbp + LOC_PLUS], 0
    mov     qword ptr [rbp + LOC_BYTES], 0
    mov     r13, rsi
    add     r13, 8              // &argv[1]
    mov     rcx, rdi
    dec     rcx                 // candidate operand count

.opt:
    test    rcx, rcx
    jz      .opt_done
    mov     rbx, [r13]
    cmp     byte ptr [rbx], '-'
    jne     .opt_done
    cmp     byte ptr [rbx + 1], 0
    je      .opt_done           // "-" operand (stdin)
    cmp     byte ptr [rbx + 1], '-'
    jne     .chk_n
    cmp     byte ptr [rbx + 2], 0
    jne     .chk_n
    add     r13, 8              // "--": end of options
    dec     rcx
    jmp     .opt_done
.chk_n:
    cmp     byte ptr [rbx + 1], 'n'
    je      .nc_num
    cmp     byte ptr [rbx + 1], 'c'
    jne     .opt_done
    mov     qword ptr [rbp + LOC_BYTES], 1
.nc_num:
    cmp     byte ptr [rbx + 2], 0
    jne     .n_joined
    add     r13, 8              // "-n" number (next argument)
    dec     rcx
    test    rcx, rcx
    jz      .n_missing
    mov     rdi, [r13]
    call    .set_count
    add     r13, 8
    dec     rcx
    jmp     .opt
.n_joined:
    lea     rdi, [rbx + 2]      // "-nnumber"
    call    .set_count
    add     r13, 8
    dec     rcx
    jmp     .opt

// .set_count: rdi = number string, possibly "+"-prefixed. Records N and plus.
.set_count:
    mov     qword ptr [rbp + LOC_PLUS], 0
    cmp     byte ptr [rdi], '+'
    jne     1f
    mov     qword ptr [rbp + LOC_PLUS], 1
    inc     rdi
1:
    call    parse_uint
    mov     [rbp + LOC_N], rax
    ret

.n_missing:
    mov     r14, 1
    lea     rdi, [rip + err_narg]
    call    err_puts
    jmp     .finish

.opt_done:
    mov     [rbp + LOC_REM], rcx

    test    rcx, rcx
    jnz     .have_ops
    mov     rbx, STDIN          // no operand -> stdin, no header
    call    .run_one
    jmp     .finish

.have_ops:
    mov     qword ptr [rbp + LOC_HDR], 0
    cmp     rcx, 1
    jbe     1f
    mov     qword ptr [rbp + LOC_HDR], 1
1:
    mov     qword ptr [rbp + LOC_FIRST], 1

.ploop:
    cmp     qword ptr [rbp + LOC_REM], 0
    je      .finish
    mov     rbx, [r13]

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
    call    .run_one
    jmp     .pnext

.pf_open:
    mov     rdi, rbx
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    call    uolt_open
    test    rax, rax
    js      .pf_err
    mov     rbx, rax            // fd
    cmp     qword ptr [rbp + LOC_HDR], 0
    je      3f
    mov     rsi, [r13]          // header name = filename
    call    print_header
3:
    call    .run_one
    mov     rdi, rbx
    call    uolt_close
    jmp     .pnext

.pf_err:
    mov     r14, 1
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

// .run_one: process descriptor rbx per the parsed N / plus / bytes flags.
.run_one:
    mov     rdi, rbx
    mov     rsi, [rbp + LOC_N]
    cmp     qword ptr [rbp + LOC_BYTES], 0
    jne     .ro_bytes
    cmp     qword ptr [rbp + LOC_PLUS], 0
    jne     1f
    call    last_lines
    ret
1:
    call    forward_from_line
    ret
.ro_bytes:
    cmp     qword ptr [rbp + LOC_PLUS], 0
    jne     2f
    call    last_bytes
    ret
2:
    call    forward_from_byte
    ret

.finish:
    mov     rax, r14
    add     rsp, 2*BUFSZ + 96
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

// ------------------------------------------------------------------ helpers

// last_lines(fd in rdi, N in rsi): print the last N lines. Seeks to find the
// start on a regular file; falls back to the sliding window on a pipe.
last_lines:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi            // fd
    mov     r12, rsi            // N
    test    r12, r12
    jz      .ll_done            // -n 0: print nothing
    mov     rdi, rbx            // end = lseek(fd, 0, SEEK_END)
    xor     rsi, rsi
    mov     rdx, SEEK_END
    call    uolt_lseek
    test    rax, rax
    js      .ll_pipe            // -ESPIPE etc -> not seekable
    jz      .ll_done            // empty file
    mov     r13, rax            // end offset (also the running chunk boundary)

    mov     qword ptr [rbp + LOC_CNT], 0    // newline count
    mov     qword ptr [rbp + LOC_FB], 1     // firstbyte flag
.bs_chunk:
    test    r13, r13
    jz      .bs_whole           // reached BOF with < N lines -> whole file
    mov     rcx, BUFSZ          // csize = min(BUFSZ, r13)
    cmp     r13, rcx
    jae     1f
    mov     rcx, r13
1:
    sub     r13, rcx            // chunkbase -= csize
    mov     [rbp + LOC_CS], rcx // csize (call-clobbered regs can't hold it)
    mov     rdi, rbx            // lseek(fd, chunkbase, SEEK_SET)
    mov     rsi, r13
    mov     rdx, SEEK_SET
    call    uolt_lseek
    mov     rdi, rbx            // read_exact(fd, buf, csize)
    mov     rsi, r15
    mov     rdx, [rbp + LOC_CS]
    call    read_exact
    mov     rdx, rax            // i = bytes available
.bs_scan:
    test    rdx, rdx
    jz      .bs_chunk           // this chunk exhausted -> previous chunk
    dec     rdx
    cmp     qword ptr [rbp + LOC_FB], 0     // firstbyte: skip one trailing newline
    je      2f
    mov     qword ptr [rbp + LOC_FB], 0
    cmp     byte ptr [r15 + rdx], 0x0a
    je      .bs_scan
2:
    cmp     byte ptr [r15 + rdx], 0x0a
    jne     .bs_scan
    mov     rax, [rbp + LOC_CNT]
    inc     rax
    mov     [rbp + LOC_CNT], rax
    cmp     rax, r12            // found N newlines?
    jne     .bs_scan
    lea     rax, [r13 + rdx + 1]    // start = chunkbase + i + 1
    jmp     .bs_emit
.bs_whole:
    xor     rax, rax            // start = 0
.bs_emit:
    mov     rdi, rbx            // lseek(fd, start, SEEK_SET)
    mov     rsi, rax
    mov     rdx, SEEK_SET
    call    uolt_lseek
    mov     rdi, rbx
    call    copy_to_eof
.ll_done:
    pop     r13
    pop     r12
    pop     rbx
    ret
.ll_pipe:
    mov     rdi, rbx
    mov     rsi, r12
    call    last_lines_pipe
    jmp     .ll_done

// last_lines_pipe(fd in rdi, N in rsi): non-seekable last-N via a sliding window
// that retains only the final BUFSZ bytes (buffer capacity is 2*BUFSZ).
last_lines_pipe:
    push    rbx
    mov     rbx, rdi            // fd
    mov     r10, rsi            // N
    test    r10, r10
    jz      .lp_fin             // -n 0: print nothing
    xor     r8, r8              // len (bytes currently held)
.lp_read:
    mov     rdi, rbx
    lea     rsi, [r15 + r8]
    mov     rdx, BUFSZ
    call    uolt_read
    test    rax, rax
    jz      .lp_eof
    js      .lp_err
    add     r8, rax             // len += got
    cmp     r8, BUFSZ
    jbe     .lp_read
    mov     rcx, r8             // drop = len - BUFSZ oldest bytes
    sub     rcx, BUFSZ
    lea     rsi, [r15 + rcx]    // src = base + drop
    mov     rdi, r15            // dst = base
    mov     r8, BUFSZ           // new len
    mov     rcx, BUFSZ          // move BUFSZ retained bytes down
    rep     movsb
    jmp     .lp_read
.lp_err:
    mov     r14, 1
    jmp     .lp_fin
.lp_eof:
    test    r8, r8
    jz      .lp_fin
    mov     r9, r8              // e = len; ignore one trailing newline
    cmp     byte ptr [r15 + r8 - 1], 0x0a
    jne     1f
    dec     r9
1:
    xor     rcx, rcx            // count
    mov     rdx, r9             // i = e
.lp_scan:
    test    rdx, rdx
    jz      .lp_whole
    dec     rdx
    cmp     byte ptr [r15 + rdx], 0x0a
    jne     .lp_scan
    inc     rcx
    cmp     rcx, r10
    jne     .lp_scan
    inc     rdx                 // start = i + 1
    jmp     .lp_emit
.lp_whole:
    xor     rdx, rdx            // start = 0
.lp_emit:
    lea     rsi, [r15 + rdx]
    mov     rax, r8
    sub     rax, rdx
    mov     rdx, rax            // length = len - start
    call    emit
.lp_fin:
    pop     rbx
    ret

// last_bytes(fd in rdi, N in rsi): print the last N bytes. Seeks on a regular
// file; falls back to a sliding window on a pipe.
last_bytes:
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     r12, rsi
    test    r12, r12
    jz      .lb_done
    mov     rdi, rbx
    xor     rsi, rsi
    mov     rdx, SEEK_END
    call    uolt_lseek
    test    rax, rax
    js      .lb_pipe
    sub     rax, r12                    // start = end - N (clamp to 0)
    jns     1f
    xor     rax, rax
1:
    mov     rdi, rbx
    mov     rsi, rax
    mov     rdx, SEEK_SET
    call    uolt_lseek
    mov     rdi, rbx
    call    copy_to_eof
.lb_done:
    pop     r12
    pop     rbx
    ret
.lb_pipe:
    mov     rdi, rbx
    mov     rsi, r12
    call    last_bytes_pipe
    jmp     .lb_done

// last_bytes_pipe(fd in rdi, N in rsi): non-seekable last-N-bytes via a sliding
// window keeping the last min(N, BUFSZ) bytes, then emitting them all.
last_bytes_pipe:
    push    rbx
    mov     rbx, rdi
    mov     r10, rsi                    // keep = min(N, BUFSZ)
    mov     rax, BUFSZ
    cmp     r10, rax
    jbe     1f
    mov     r10, rax
1:
    xor     r8, r8                      // len
.lbp_read:
    mov     rdi, rbx
    lea     rsi, [r15 + r8]
    mov     rdx, BUFSZ
    call    uolt_read
    test    rax, rax
    jz      .lbp_eof
    js      .lbp_fin
    add     r8, rax
    cmp     r8, r10
    jbe     .lbp_read
    mov     rcx, r8
    sub     rcx, r10                    // drop oldest
    lea     rsi, [r15 + rcx]
    mov     rdi, r15
    mov     r8, r10
    mov     rcx, r10
    rep     movsb
    jmp     .lbp_read
.lbp_eof:
    test    r8, r8
    jz      .lbp_fin
    mov     rsi, r15
    mov     rdx, r8
    call    emit
.lbp_fin:
    pop     rbx
    ret

// forward_from_byte(fd in rdi, startbyte in rsi): copy from byte `startbyte`
// (1-based) to EOF. startbyte <= 1 copies everything.
forward_from_byte:
    push    rbx
    mov     rbx, rdi
    mov     r10, rsi
    dec     r10                         // bytes to skip
    jle     .fb_all
.fb_read:
    mov     rdi, rbx
    mov     rsi, r15
    mov     rdx, BUFSZ
    call    uolt_read
    test    rax, rax
    jz      .fb_done
    js      .fb_err
    cmp     r10, rax
    jae     .fb_skipblock
    lea     rsi, [r15 + r10]            // emit the rest of this block
    mov     rdx, rax
    sub     rdx, r10
    call    emit
    mov     rdi, rbx
    call    copy_to_eof
    jmp     .fb_done
.fb_skipblock:
    sub     r10, rax
    jmp     .fb_read
.fb_all:
    mov     rdi, rbx
    call    copy_to_eof
.fb_done:
    pop     rbx
    ret
.fb_err:
    mov     r14, 1
    pop     rbx
    ret

// forward_from_line(fd in rdi, startline in rsi): copy from line `startline`
// (1-based) to EOF. startline <= 1 copies everything. Streams, so it works on
// both files and pipes.
forward_from_line:
    push    rbx
    mov     rbx, rdi            // fd
    mov     r10, rsi            // startline
    dec     r10                 // lines to skip = startline - 1
    jle     .ff_all
.ff_read:
    mov     rdi, rbx
    mov     rsi, r15
    mov     rdx, BUFSZ
    call    uolt_read
    test    rax, rax
    jz      .ff_done            // EOF before reaching start -> nothing
    js      .ff_err
    mov     r8, rax             // block length
    xor     rdx, rdx            // i = 0
.ff_scan:
    cmp     rdx, r8
    jae     .ff_read            // whole block skipped, read the next
    cmp     byte ptr [r15 + rdx], 0x0a
    jne     1f
    dec     r10
    jz      .ff_rest            // reached the start line
1:
    inc     rdx
    jmp     .ff_scan
.ff_rest:
    inc     rdx                 // position just after the newline
    lea     rsi, [r15 + rdx]
    mov     rax, r8
    sub     rax, rdx
    mov     rdx, rax
    call    emit
    mov     rdi, rbx
    call    copy_to_eof
    jmp     .ff_done
.ff_all:
    mov     rdi, rbx
    call    copy_to_eof
    jmp     .ff_done
.ff_err:
    mov     r14, 1
.ff_done:
    pop     rbx
    ret

// copy_to_eof(fd in rdi): copy from the current file position to EOF. Uses the
// buffer at r15; sets r14 on a read/write error.
copy_to_eof:
    mov     r8, rdi             // fd (survives syscalls)
1:
    mov     rdi, r8
    mov     rsi, r15
    mov     rdx, BUFSZ
    call    uolt_read
    test    rax, rax
    jz      3f
    js      2f
    mov     r9, r15             // drain rax bytes
    mov     r10, rax
4:
    mov     rdi, STDOUT
    mov     rsi, r9
    mov     rdx, r10
    call    uolt_write
    test    rax, rax
    js      2f
    add     r9, rax
    sub     r10, rax
    jnz     4b
    jmp     1b
2:
    mov     r14, 1
3:
    ret

// read_exact(fd in rdi, buf in rsi, count in rdx) -> rax bytes read. Loops until
// count bytes are read or EOF/error is hit.
read_exact:
    push    rbx
    mov     rbx, rdi            // fd
    mov     r8, rsi             // buf
    mov     r9, rdx             // remaining
    xor     r10, r10            // total
1:
    test    r9, r9
    jz      2f
    mov     rdi, rbx
    lea     rsi, [r8 + r10]
    mov     rdx, r9
    call    uolt_read
    test    rax, rax
    jle     2f                  // 0 (EOF) or < 0 (error) -> stop
    add     r10, rax
    sub     r9, rax
    jmp     1b
2:
    mov     rax, r10
    pop     rbx
    ret

// emit(buf in rsi, len in rdx): drain to stdout, tolerating short writes.
emit:
    mov     r9, rsi
    mov     r10, rdx
1:
    test    r10, r10
    jz      2f
    mov     rdi, STDOUT
    mov     rsi, r9
    mov     rdx, r10
    call    uolt_write
    test    rax, rax
    js      3f
    add     r9, rax
    sub     r10, rax
    jmp     1b
3:
    mov     r14, 1
2:
    ret

// print_header(name in rsi): write "==> name <==\n" to stdout, preceded by a
// blank line except for the first header. Preserves rbx (the caller's fd).
print_header:
    push    rbx
    mov     rbx, rsi
    cmp     qword ptr [rbp + LOC_FIRST], 0
    jne     1f
    mov     rdi, STDOUT
    lea     rsi, [rip + nl_char]
    mov     rdx, 1
    call    uolt_write
1:
    mov     qword ptr [rbp + LOC_FIRST], 0
    mov     rdi, STDOUT
    lea     rsi, [rip + hdr_pre]
    mov     rdx, 4
    call    uolt_write
    mov     rdi, rbx
    call    uolt_strlen
    mov     rdx, rax
    mov     rsi, rbx
    mov     rdi, STDOUT
    call    uolt_write
    mov     rdi, STDOUT
    lea     rsi, [rip + hdr_suf]
    mov     rdx, 5
    call    uolt_write
    pop     rbx
    ret

// parse_uint(rdi = ASCIZ digits) -> rax. Lenient: stops at the first non-digit.
// Preserves rcx for the option loop; clobbers rax, rdx, rdi.
parse_uint:
    xor     rax, rax
1:
    movzx   rdx, byte ptr [rdi]
    sub     rdx, '0'
    cmp     rdx, 9
    ja      2f
    imul    rax, rax, 10
    add     rax, rdx
    inc     rdi
    jmp     1b
2:
    ret

// err_puts(rdi = ASCIZ) -> stderr; length via strlen (no magic numbers).
err_puts:
    mov     r8, rdi
    call    uolt_strlen
    mov     rdx, rax
    mov     rsi, r8
    mov     rdi, STDERR
    jmp     uolt_write

// Read-only text kept in the code segment (folded into .text on Linux, __TEXT on
// macOS). Reached only via lea, never executed.
hdr_pre:    .ascii  "==> "
hdr_suf:    .ascii  " <==\n"
nl_char:    .byte   0x0a
stdin_name: .asciz  "standard input"
err_pre:    .asciz  "uolt-tail: "
err_suf:    .asciz  ": cannot open\n"
err_narg:   .asciz  "uolt-tail: option requires an argument -- n\n"
