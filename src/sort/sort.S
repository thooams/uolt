// src/sort/sort.S - the `sort` utility (lexicographic).
//
// sort [-r] [file...]: read all input lines, sort them in C-locale byte order
// (-r reverses), and write them out. With no file operand standard input is
// read; several files are concatenated. Numeric (-n), unique (-u), key, and
// merge options are out of scope in v1.
//
// Sorting needs all the lines at once, which has no unbounded heap-free form, so
// the input is held in a fixed 1 MB text buffer with a fixed line-pointer array,
// both on the stack (no heap, Principle IV). Input beyond the buffer is dropped
// (a documented bound). The sort is a simple in-place insertion sort of the
// pointer array (adequate for the bounded size).
//
// Called as uolt_main(argc in rdi, argv in rsi) by the per-OS entry shim.
//
// Global registers: r13 = text buffer, r15 = line-pointer array, r14 = line
//   count. Stack local [rbp-48] = reverse flag.

#include "uolt.inc"

.set STDIN,    0
.set STDOUT,   1
.set STDERR,   2
.set O_RDONLY, 0
.set TBUF,     1048576          // 1 MB of input text
.set MAXLINES, 131072           // up to 128 K lines (pointer array = 1 MB)

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
    sub     rsp, TBUF + MAXLINES*8 + 16
    mov     r13, rsp                    // text buffer
    lea     r15, [rsp + TBUF]           // line-pointer array
    xor     r14, r14                    // line count
    mov     qword ptr [rbp - 48], 0     // reverse flag
    xor     r12, r12                    // text fill (bytes read so far)

    mov     rbx, rdi
    dec     rbx                         // operand count
    lea     r10, [rsi + 8]              // &argv walk (kept in r10 across reads? no)
    mov     [rbp - 56], r10             // save argv pointer

    // options
.opt:
    test    rbx, rbx
    jz      .files
    mov     r10, [rbp - 56]
    mov     rax, [r10]
    cmp     byte ptr [rax], '-'
    jne     .files
    cmp     byte ptr [rax + 1], 0
    je      .files                      // "-" -> stdin operand
    cmp     byte ptr [rax + 1], 'r'
    jne     1f
    cmp     byte ptr [rax + 2], 0
    jne     1f
    mov     qword ptr [rbp - 48], 1     // -r
    add     qword ptr [rbp - 56], 8
    dec     rbx
    jmp     .opt
1:
    cmp     byte ptr [rax + 1], '-'
    jne     .files
    cmp     byte ptr [rax + 2], 0
    jne     .files
    add     qword ptr [rbp - 56], 8     // "--"
    dec     rbx

.files:
    test    rbx, rbx
    jnz     .floop
    mov     rdi, STDIN                  // no operands -> read stdin
    call    read_into
    jmp     .split
.floop:
    test    rbx, rbx
    jz      .split
    mov     r10, [rbp - 56]
    mov     rax, [r10]
    // "-" means stdin
    cmp     byte ptr [rax], '-'
    jne     2f
    cmp     byte ptr [rax + 1], 0
    jne     2f
    mov     rdi, STDIN
    call    read_into
    jmp     .fnext
2:
    mov     rdi, rax
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    call    uolt_open
    test    rax, rax
    js      .fnext                      // unopenable file: skip (best-effort)
    mov     rdi, rax
    push    rax
    call    read_into
    pop     rdi
    call    uolt_close
.fnext:
    add     qword ptr [rbp - 56], 8
    dec     rbx
    jmp     .floop

.split:
    // Turn the text into NUL-terminated lines and record each start pointer.
    // r12 = total bytes. Walk [r13, r13+r12): each run up to '\n' is a line.
    xor     rcx, rcx                    // i
.sp_line:
    cmp     rcx, r12
    jae     .sp_done
    // record line start
    cmp     r14, MAXLINES
    jae     .sp_scan_only               // pointer array full: stop recording
    lea     rax, [r13 + rcx]
    mov     [r15 + r14*8], rax
    inc     r14
.sp_scan_only:
    // scan to newline or end
.sp_find:
    cmp     rcx, r12
    jae     .sp_done
    cmp     byte ptr [r13 + rcx], 0x0a
    je      .sp_nl
    inc     rcx
    jmp     .sp_find
.sp_nl:
    mov     byte ptr [r13 + rcx], 0     // terminate the line
    inc     rcx
    jmp     .sp_line
.sp_done:

    // Insertion sort of the pointer array [0, r14).
    mov     rbx, 1                      // i = 1
.is_out:
    cmp     rbx, r14
    jae     .emit
    mov     r9, [r15 + rbx*8]           // key
    mov     r8, rbx
    dec     r8                          // j = i - 1
.is_in:
    test    r8, r8
    js      .is_place
    mov     rdi, [r15 + r8*8]           // a = p[j]
    mov     rsi, r9                     // b = key
    call    line_cmp                    // rax < 0 if a < b
    // ascending: shift while p[j] > key ; -r flips
    cmp     qword ptr [rbp - 48], 0
    jne     .is_rev
    test    rax, rax
    jle     .is_place                   // p[j] <= key: stop
    jmp     .is_shift
.is_rev:
    test    rax, rax
    jge     .is_place                   // p[j] >= key: stop (reverse)
.is_shift:
    mov     rax, [r15 + r8*8]
    mov     [r15 + r8*8 + 8], rax
    dec     r8
    jmp     .is_in
.is_place:
    mov     [r15 + r8*8 + 8], r9
    inc     rbx
    jmp     .is_out

.emit:
    xor     rbx, rbx                    // i = 0
.em_loop:
    cmp     rbx, r14
    jae     .fin
    mov     rdi, [r15 + rbx*8]
    call    put_line
    inc     rbx
    jmp     .em_loop

.fin:
    xor     eax, eax
    add     rsp, TBUF + MAXLINES*8 + 16
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

// read_into(fd in rdi): append the descriptor's bytes to the text buffer at
// [r13 + r12], updating r12 (total). Stops at the buffer limit. Preserves the
// caller's operand registers (rbx and [rbp-56]).
read_into:
    push    rbx
    mov     rbx, rdi                    // fd
.ri_read:
    mov     rdx, TBUF
    sub     rdx, r12                    // space left
    jz      .ri_done                    // buffer full
    mov     rdi, rbx
    lea     rsi, [r13 + r12]
    call    uolt_read
    test    rax, rax
    jle     .ri_done                    // EOF or error
    add     r12, rax
    jmp     .ri_read
.ri_done:
    pop     rbx
    ret

// line_cmp(rdi = a, rsi = b) -> rax: <0 if a<b, 0 if equal, >0 if a>b (unsigned
// byte comparison of NUL-terminated strings).
line_cmp:
    xor     rcx, rcx
1:
    movzx   eax, byte ptr [rdi + rcx]
    movzx   edx, byte ptr [rsi + rcx]
    cmp     eax, edx
    jne     2f
    test    eax, eax
    jz      3f                          // both hit NUL: equal
    inc     rcx
    jmp     1b
2:
    sub     eax, edx                    // sign gives the order
    cdqe                                // sign-extend eax -> rax (else zero-extended)
    ret
3:
    xor     eax, eax
    ret

// put_line(rdi = ASCIZ line): write the line and a newline to stdout.
put_line:
    mov     r9, rdi
    call    uolt_strlen
    mov     rdx, rax
    mov     rsi, r9
    mov     rdi, STDOUT
    call    uolt_write
    mov     rdi, STDOUT
    lea     rsi, [rip + nl_char]
    mov     rdx, 1
    jmp     uolt_write

nl_char: .byte 0x0a
