// src/sort/sort.S - the `sort` utility (lexicographic).
//
// sort [-rnufb] [file...]: read all input lines, sort them in C-locale byte
// order, and write them out. -r reverses, -n compares leading integers, -u drops
// adjacent equal-key lines, -f folds case, -b ignores leading blanks. With no
// file operand standard input is read; several files are concatenated. Key
// (-k/-t) and external merge are out of scope in v1. Ties keep input order
// (stable), matching GNU's default last-resort compare.
//
// Sorting needs every line in memory at once. Rather than a fixed stack buffer
// that would silently truncate large input, the text and line-pointer arrays are
// mmap'd anonymous regions that GROW on demand (double, copy, unmap the old one),
// so cost tracks the actual input and the only limit is available memory - a real
// out-of-memory is reported, never a silent truncation. (Principle IV permits an
// explicit, failure-checked mmap when a fixed buffer cannot do the job; this is
// not a hidden heap.) The sort is a stable bottom-up merge sort (O(n log n)) over
// the pointer array, with a third region as ping-pong scratch.
//
// Line pointers are computed only after all input is read, so growing/moving the
// text region during reading is safe (no pointers into it yet).
//
// Called as uolt_main(argc in rdi, argv in rsi) by the per-OS entry shim.
//
// Global registers: r13 = text region, r15 = current line-pointer array, r14 =
//   line count, r12 = text fill during read (reused as the merge run width), rbx
//   = operand count during argument handling.

#include "uolt.inc"

.set STDIN,    0
.set STDOUT,   1
.set STDERR,   2
.set O_RDONLY, 0

.set TEXT_START, 0x800000               // initial text region: 8 MiB
.set PTR_START,  0x100000                // initial pointer array: 1 MiB (128 K lines)
.set OBSIZE,     0x10000                 // output buffer: 64 KiB (batches writes)

// Stack locals (below the five pushed callee-saved registers at [rbp-8..-40]).
.set LOC_FLAGS,   -48
.set LOC_ARGV,    -56
.set LOC_AUX,     -64                    // scratch pointer array
.set LOC_SRC,     -72                    // merge ping-pong: current source array
.set LOC_DST,     -80                    // merge ping-pong: current dest array
.set LOC_I,       -88                    // run start index in a pass
.set LOC_MID,     -96
.set LOC_END,     -104
.set LOC_LI,      -112                   // merge cursors: left, right, dest
.set LOC_RI,      -120
.set LOC_DI,      -128
.set LOC_TCAP,    -136                   // text region capacity
.set LOC_PCAP,    -144                   // pointer array capacity (bytes)
.set LOC_NEWCAP,  -152                   // scratch across a grow
.set LOC_NEWBASE, -160
.set LOC_OBLEN,   -168                   // bytes buffered in OBUF
.set OBUFOFF,     -65704                  // output buffer [OBUFOFF, LOC_OBLEN)
.set FRAME,       65792

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
    sub     rsp, FRAME
    cld

    // Capture argv/argc before mmap clobbers rdi/rsi. rbx (operand count) is
    // callee-saved and survives the syscalls.
    lea     rax, [rsi + 8]              // &argv[1]
    mov     [rbp + LOC_ARGV], rax
    lea     rbx, [rdi - 1]              // operand count
    mov     qword ptr [rbp + LOC_FLAGS], 0

    mov     rdi, TEXT_START
    call    uolt_mmap_anon
    test    rax, rax
    js      mem_err
    mov     r13, rax
    mov     qword ptr [rbp + LOC_TCAP], TEXT_START
    mov     rdi, PTR_START
    call    uolt_mmap_anon
    test    rax, rax
    js      mem_err
    mov     r15, rax
    mov     qword ptr [rbp + LOC_PCAP], PTR_START

    xor     r14, r14                    // line count
    xor     r12, r12                    // text fill
    mov     qword ptr [rbp + LOC_OBLEN], 0

.opt:
    test    rbx, rbx
    jz      .files
    mov     r10, [rbp + LOC_ARGV]
    mov     rax, [r10]
    cmp     byte ptr [rax], '-'
    jne     .files
    cmp     byte ptr [rax + 1], 0
    je      .files                      // "-" -> stdin operand
    cmp     byte ptr [rax + 1], '-'
    jne     .optletters
    cmp     byte ptr [rax + 2], 0
    jne     .optletters
    add     qword ptr [rbp + LOC_ARGV], 8   // "--"
    dec     rbx
    jmp     .files
.optletters:
    lea     r11, [rax + 1]
.optf:
    movzx   ecx, byte ptr [r11]
    test    cl, cl
    jz      .optdone
    cmp     cl, 'r'
    jne     5f
    or      qword ptr [rbp + LOC_FLAGS], 1
    jmp     .optfn
5:
    cmp     cl, 'n'
    jne     6f
    or      qword ptr [rbp + LOC_FLAGS], 2
    jmp     .optfn
6:
    cmp     cl, 'u'
    jne     7f
    or      qword ptr [rbp + LOC_FLAGS], 4
    jmp     .optfn
7:
    cmp     cl, 'f'
    jne     8f
    or      qword ptr [rbp + LOC_FLAGS], 8
    jmp     .optfn
8:
    cmp     cl, 'b'
    jne     .files
    or      qword ptr [rbp + LOC_FLAGS], 16
.optfn:
    inc     r11
    jmp     .optf
.optdone:
    add     qword ptr [rbp + LOC_ARGV], 8
    dec     rbx
    jmp     .opt

.files:
    test    rbx, rbx
    jnz     .floop
    mov     rdi, STDIN
    call    read_into
    jmp     .split
.floop:
    test    rbx, rbx
    jz      .split
    mov     r10, [rbp + LOC_ARGV]
    mov     rax, [r10]
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
    js      .fnext
    mov     rdi, rax
    push    rax
    call    read_into
    pop     rdi
    call    uolt_close
.fnext:
    add     qword ptr [rbp + LOC_ARGV], 8
    dec     rbx
    jmp     .floop

.split:
    // Turn the text into NUL-terminated lines and record each start pointer.
    xor     rcx, rcx                    // i
.sp_line:
    cmp     rcx, r12
    jae     .sp_done
    // ensure room for one more pointer
    mov     rax, r14
    shl     rax, 3
    cmp     rax, [rbp + LOC_PCAP]
    jb      1f
    mov     [rbp + LOC_I], rcx          // preserve the scan index across grow_ptr
    call    grow_ptr
    mov     rcx, [rbp + LOC_I]
1:
    lea     rax, [r13 + rcx]
    mov     [r15 + r14*8], rax
    inc     r14
.sp_find:
    cmp     rcx, r12
    jae     .sp_done
    cmp     byte ptr [r13 + rcx], 0x0a
    je      .sp_nl
    inc     rcx
    jmp     .sp_find
.sp_nl:
    mov     byte ptr [r13 + rcx], 0
    inc     rcx
    jmp     .sp_line
.sp_done:
    // Scratch array of the same capacity as the pointer array (>= n entries).
    mov     rdi, [rbp + LOC_PCAP]
    call    uolt_mmap_anon
    test    rax, rax
    js      mem_err
    mov     [rbp + LOC_AUX], rax

    call    merge_sort                  // sort r15[0, r14); result left in r15

.emit:
    xor     rbx, rbx
.em_loop:
    cmp     rbx, r14
    jae     .fin
    mov     rdi, [r15 + rbx*8]
    test    qword ptr [rbp + LOC_FLAGS], 4  // -u: drop lines equal to the previous
    jz      .em_print
    test    rbx, rbx
    jz      .em_print
    mov     rdi, [r15 + rbx*8 - 8]
    mov     rsi, [r15 + rbx*8]
    call    key_cmp
    test    rax, rax
    jz      .em_skip
    mov     rdi, [r15 + rbx*8]
.em_print:
    call    put_line
.em_skip:
    inc     rbx
    jmp     .em_loop

.fin:
    call    ob_flush
    xor     eax, eax
    jmp     .epi
mem_err:
    lea     rdi, [rip + err_nomem]
    mov     r10, rdi
    call    uolt_strlen
    mov     rdx, rax
    mov     rsi, r10
    mov     rdi, STDERR
    call    uolt_write
    mov     eax, 2
.epi:
    lea     rsp, [rbp - 40]
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

// grow_text(): double the text region, copy the r12 bytes read so far into it,
// unmap the old one, and update r13 / LOC_TCAP.
grow_text:
    mov     rax, [rbp + LOC_TCAP]
    add     rax, rax
    mov     [rbp + LOC_NEWCAP], rax
    mov     rdi, rax
    call    uolt_mmap_anon
    test    rax, rax
    js      mem_err
    mov     [rbp + LOC_NEWBASE], rax
    mov     rdi, rax                    // dst
    mov     rsi, r13                    // src
    mov     rcx, r12                    // bytes used
    rep     movsb
    mov     rdi, r13                    // unmap old
    mov     rsi, [rbp + LOC_TCAP]
    call    uolt_munmap
    mov     r13, [rbp + LOC_NEWBASE]
    mov     rax, [rbp + LOC_NEWCAP]
    mov     [rbp + LOC_TCAP], rax
    ret

// grow_ptr(): double the pointer array, copy the r14 pointers into it, unmap the
// old one, and update r15 / LOC_PCAP.
grow_ptr:
    mov     rax, [rbp + LOC_PCAP]
    add     rax, rax
    mov     [rbp + LOC_NEWCAP], rax
    mov     rdi, rax
    call    uolt_mmap_anon
    test    rax, rax
    js      mem_err
    mov     [rbp + LOC_NEWBASE], rax
    mov     rdi, rax
    mov     rsi, r15
    mov     rcx, r14
    shl     rcx, 3                      // r14 * 8 bytes
    rep     movsb
    mov     rdi, r15
    mov     rsi, [rbp + LOC_PCAP]
    call    uolt_munmap
    mov     r15, [rbp + LOC_NEWBASE]
    mov     rax, [rbp + LOC_NEWCAP]
    mov     [rbp + LOC_PCAP], rax
    ret

// read_into(fd in rdi): append the descriptor's bytes to the text region at
// [r13 + r12], growing the region when it fills. Preserves rbx and LOC_ARGV.
read_into:
    push    rbx
    mov     rbx, rdi                    // fd
.ri_read:
    mov     rax, [rbp + LOC_TCAP]
    cmp     r12, rax
    jb      1f
    call    grow_text
1:
    mov     rdx, [rbp + LOC_TCAP]
    sub     rdx, r12                    // space left (> 0 after any grow)
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

// merge_sort(): stable bottom-up merge sort of r15[0, r14) using LOC_AUX as
// ping-pong scratch. On return r15 points at whichever array holds the result.
merge_sort:
    cmp     r14, 2
    jb      .ms_ret
    mov     rax, r15
    mov     [rbp + LOC_SRC], rax
    mov     rax, [rbp + LOC_AUX]
    mov     [rbp + LOC_DST], rax
    mov     r12, 1                      // run width
.ms_pass:
    cmp     r12, r14
    jae     .ms_finish
    mov     qword ptr [rbp + LOC_I], 0
.ms_run:
    mov     rax, [rbp + LOC_I]
    cmp     rax, r14
    jae     .ms_swap
    add     rax, r12                    // mid = min(i + width, n)
    cmp     rax, r14
    jbe     1f
    mov     rax, r14
1:
    mov     [rbp + LOC_MID], rax
    add     rax, r12                    // end = min(mid + width, n)
    cmp     rax, r14
    jbe     2f
    mov     rax, r14
2:
    mov     [rbp + LOC_END], rax
    mov     rax, [rbp + LOC_I]
    mov     [rbp + LOC_LI], rax
    mov     [rbp + LOC_DI], rax
    mov     rax, [rbp + LOC_MID]
    mov     [rbp + LOC_RI], rax
.mg_loop:
    mov     rax, [rbp + LOC_LI]
    cmp     rax, [rbp + LOC_MID]
    jae     .mg_rest_right
    mov     rax, [rbp + LOC_RI]
    cmp     rax, [rbp + LOC_END]
    jae     .mg_rest_left
    mov     rcx, [rbp + LOC_SRC]
    mov     rax, [rbp + LOC_LI]
    mov     rdi, [rcx + rax*8]
    mov     rax, [rbp + LOC_RI]
    mov     rsi, [rcx + rax*8]
    call    line_cmp
    test    qword ptr [rbp + LOC_FLAGS], 1
    jz      3f
    neg     rax                         // -r reverses the whole comparison
3:
    test    rax, rax
    jle     .mg_take_left               // a <= b: take left (stable on ties)
    mov     rcx, [rbp + LOC_SRC]
    mov     rax, [rbp + LOC_RI]
    mov     rdx, [rcx + rax*8]
    mov     rcx, [rbp + LOC_DST]
    mov     rax, [rbp + LOC_DI]
    mov     [rcx + rax*8], rdx
    inc     qword ptr [rbp + LOC_RI]
    inc     qword ptr [rbp + LOC_DI]
    jmp     .mg_loop
.mg_take_left:
    mov     rcx, [rbp + LOC_SRC]
    mov     rax, [rbp + LOC_LI]
    mov     rdx, [rcx + rax*8]
    mov     rcx, [rbp + LOC_DST]
    mov     rax, [rbp + LOC_DI]
    mov     [rcx + rax*8], rdx
    inc     qword ptr [rbp + LOC_LI]
    inc     qword ptr [rbp + LOC_DI]
    jmp     .mg_loop
.mg_rest_left:
    mov     rax, [rbp + LOC_LI]
    cmp     rax, [rbp + LOC_MID]
    jae     .mg_run_done
    mov     rcx, [rbp + LOC_SRC]
    mov     rdx, [rcx + rax*8]
    mov     rcx, [rbp + LOC_DST]
    mov     rax, [rbp + LOC_DI]
    mov     [rcx + rax*8], rdx
    inc     qword ptr [rbp + LOC_LI]
    inc     qword ptr [rbp + LOC_DI]
    jmp     .mg_rest_left
.mg_rest_right:
    mov     rax, [rbp + LOC_RI]
    cmp     rax, [rbp + LOC_END]
    jae     .mg_run_done
    mov     rcx, [rbp + LOC_SRC]
    mov     rdx, [rcx + rax*8]
    mov     rcx, [rbp + LOC_DST]
    mov     rax, [rbp + LOC_DI]
    mov     [rcx + rax*8], rdx
    inc     qword ptr [rbp + LOC_RI]
    inc     qword ptr [rbp + LOC_DI]
    jmp     .mg_rest_right
.mg_run_done:
    mov     rax, r12                    // i += 2 * width
    add     rax, r12
    add     [rbp + LOC_I], rax
    jmp     .ms_run
.ms_swap:
    mov     rax, [rbp + LOC_SRC]
    mov     rcx, [rbp + LOC_DST]
    mov     [rbp + LOC_SRC], rcx
    mov     [rbp + LOC_DST], rax
    add     r12, r12                    // width *= 2
    jmp     .ms_pass
.ms_finish:
    mov     rax, [rbp + LOC_SRC]
    mov     r15, rax
.ms_ret:
    ret

// line_cmp(rdi = a, rsi = b) -> rax: key comparison with a raw-byte last-resort
// tiebreak (matches GNU sort's default so ties are deterministic).
line_cmp:
    push    rdi
    push    rsi
    call    key_cmp
    test    rax, rax
    jnz     .lc_done
    pop     rsi
    pop     rdi
    xor     rcx, rcx
.lc_raw:
    movzx   eax, byte ptr [rdi + rcx]
    movzx   edx, byte ptr [rsi + rcx]
    cmp     eax, edx
    jne     .lc_rdiff
    test    eax, eax
    jz      .lc_req
    inc     rcx
    jmp     .lc_raw
.lc_rdiff:
    sub     eax, edx
    cdqe
    ret
.lc_req:
    xor     eax, eax
    ret
.lc_done:
    add     rsp, 16
    ret

// key_cmp(rdi = a, rsi = b) -> rax: <0/0/>0 on the sort keys. Byte compare with
// -f (fold) and -b (ignore leading blanks), or numeric under -n.
key_cmp:
    test    qword ptr [rbp + LOC_FLAGS], 2
    jnz     num_cmp
    test    qword ptr [rbp + LOC_FLAGS], 16
    jz      .kc_scan
.kc_ba:
    movzx   eax, byte ptr [rdi]
    cmp     al, ' '
    je      1f
    cmp     al, 0x09
    jne     .kc_bb
1:
    inc     rdi
    jmp     .kc_ba
.kc_bb:
    movzx   eax, byte ptr [rsi]
    cmp     al, ' '
    je      1f
    cmp     al, 0x09
    jne     .kc_scan
1:
    inc     rsi
    jmp     .kc_bb
.kc_scan:
    xor     rcx, rcx
1:
    movzx   eax, byte ptr [rdi + rcx]
    movzx   edx, byte ptr [rsi + rcx]
    test    qword ptr [rbp + LOC_FLAGS], 8
    jz      4f
    cmp     al, 'A'
    jb      7f
    cmp     al, 'Z'
    ja      7f
    add     al, 0x20
7:
    cmp     dl, 'A'
    jb      4f
    cmp     dl, 'Z'
    ja      4f
    add     dl, 0x20
4:
    cmp     eax, edx
    jne     2f
    test    eax, eax
    jz      3f
    inc     rcx
    jmp     1b
2:
    sub     eax, edx
    cdqe
    ret
3:
    xor     eax, eax
    ret

// num_cmp(rdi = a, rsi = b) -> rax: compare the leading integers of two lines.
num_cmp:
    mov     r11, rsi
    call    parse_num
    mov     r10, rax
    mov     rdi, r11
    call    parse_num
    cmp     r10, rax
    jl      .nc_lt
    jg      .nc_gt
    xor     eax, eax
    ret
.nc_lt:
    mov     rax, -1
    ret
.nc_gt:
    mov     rax, 1
    ret

// parse_num(rdi = ASCIZ) -> rax: leading integer. Uses rax/rcx/rdx/rdi;
// preserves r8-r11.
parse_num:
    xor     rax, rax
    xor     rdx, rdx
.pn_sp:
    movzx   ecx, byte ptr [rdi]
    cmp     cl, ' '
    je      .pn_adv
    cmp     cl, 0x09
    jne     .pn_sign
.pn_adv:
    inc     rdi
    jmp     .pn_sp
.pn_sign:
    cmp     cl, '-'
    jne     1f
    mov     rdx, 1
    inc     rdi
    jmp     .pn_dig
1:
    cmp     cl, '+'
    jne     .pn_dig
    inc     rdi
.pn_dig:
    movzx   ecx, byte ptr [rdi]
    sub     cl, '0'
    cmp     cl, 9
    ja      .pn_done
    imul    rax, rax, 10
    movzx   rcx, cl
    add     rax, rcx
    inc     rdi
    jmp     .pn_dig
.pn_done:
    test    rdx, rdx
    jz      2f
    neg     rax
2:
    ret

// put_line(rdi = ASCIZ line): append the line and a newline to the output
// buffer. Preserves rbx (the emit loop counter).
put_line:
    mov     r9, rdi
    call    uolt_strlen                 // rax = length
    mov     rsi, r9
    mov     rdx, rax
    call    ob_put
    lea     rsi, [rip + nl_char]
    mov     rdx, 1
    call    ob_put
    ret

// ob_put(rsi = src, rdx = len): append len bytes to OBUF, flushing when full.
// Uses a block copy (rep movsb) so large output is memory-bound, not syscall-
// bound. Preserves rbx / r12-r15.
ob_put:
.op_l:
    test    rdx, rdx
    jz      .op_ret
    mov     rcx, [rbp + LOC_OBLEN]
    cmp     rcx, OBSIZE
    jb      1f
    push    rsi
    push    rdx
    call    ob_flush
    pop     rdx
    pop     rsi
    xor     rcx, rcx
1:
    mov     rax, OBSIZE
    sub     rax, rcx                    // space left in OBUF
    cmp     rax, rdx
    jbe     2f
    mov     rax, rdx                    // copy = min(space, len)
2:
    lea     rdi, [rbp + OBUFOFF]
    add     rdi, rcx
    mov     r8, rax                     // remember the copy count
    mov     rcx, rax
    rep     movsb                       // src (rsi) and dst advance; DF is clear
    add     [rbp + LOC_OBLEN], r8
    sub     rdx, r8
    jmp     .op_l
.op_ret:
    ret

// ob_flush(): write OBUF to stdout and reset it.
ob_flush:
    mov     rdx, [rbp + LOC_OBLEN]
    test    rdx, rdx
    jz      .obf_ret
    lea     rsi, [rbp + OBUFOFF]
    mov     rdi, STDOUT
    call    uolt_write
    mov     qword ptr [rbp + LOC_OBLEN], 0
.obf_ret:
    ret

nl_char:   .byte 0x0a
err_nomem: .asciz "uolt-sort: out of memory\n"
