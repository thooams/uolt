// src/tr/tr.S - the `tr` utility (translate / delete).
//
// tr set1 set2   translate bytes in set1 to the matching byte of set2
// tr -d set1     delete bytes in set1
//
// Each set is a sequence of literal bytes and ranges (e.g. a-z). For translation
// a byte in set1 is mapped to the byte at the same index in set2, or to set2's
// last byte if set2 is shorter (the common tr behavior). Backslash escapes and
// -s/-c are out of scope in v1.
//
// A 256-entry translation table and a 256-entry delete flag are built on the
// stack (no heap, Principle IV). Input is transformed block by block through a
// 64 KB buffer.
//
// Called as uolt_main(argc in rdi, argv in rsi) by the per-OS entry shim.
//
// Global registers: r15 = I/O buffer; r14 = table base (256 map + 256 delete).
//   Stack local [-48] = delete-mode flag.

#include "uolt.inc"

.set STDIN,  0
.set STDOUT, 1
.set STDERR, 2
.set BUFSZ,  65536

.set LOC_DEL, -48

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
    sub     rsp, 2*BUFSZ + 1024 + 64
    mov     r15, rsp                    // I/O buffer (in at r15, out at r15+BUFSZ)
    lea     r14, [rsp + 2*BUFSZ]        // tables: map[256] then del[256]
    mov     qword ptr [rbp + LOC_DEL], 0

    mov     r12, rdi
    dec     r12
    lea     r13, [rsi + 8]

    // -d ?
    test    r12, r12
    jz      .usage
    mov     rbx, [r13]
    cmp     byte ptr [rbx], '-'
    jne     .init
    cmp     byte ptr [rbx + 1], 'd'
    jne     .maybe_ddash
    cmp     byte ptr [rbx + 2], 0
    jne     .maybe_ddash
    mov     qword ptr [rbp + LOC_DEL], 1
    add     r13, 8
    dec     r12
    jmp     .init
.maybe_ddash:
    cmp     byte ptr [rbx + 1], '-'
    jne     .init
    cmp     byte ptr [rbx + 2], 0
    jne     .init
    add     r13, 8
    dec     r12
.init:
    // Build an identity map and a clear delete table.
    xor     rcx, rcx
.id:
    mov     al, cl
    mov     [r14 + rcx], al             // map[c] = c
    mov     byte ptr [r14 + 256 + rcx], 0
    inc     rcx
    cmp     rcx, 256
    jne     .id

    cmp     qword ptr [rbp + LOC_DEL], 0
    jne     .build_delete

    // translate: need set1 and set2
    cmp     r12, 2
    jl      .usage
    mov     rdi, [r13]                  // set1 -> expand into out-buffer area (scratch)
    lea     rsi, [r15 + BUFSZ]
    call    expand_set
    mov     rbx, rax                    // len1
    mov     rdi, [r13 + 8]              // set2 -> expand into I/O buffer (scratch)
    mov     rsi, r15
    call    expand_set
    mov     r8, rax                     // len2
    test    r8, r8
    jz      .usage
    // map[set1[i]] = set2[min(i, len2-1)]
    xor     rcx, rcx
.mp:
    cmp     rcx, rbx
    jae     .run
    movzx   r9, byte ptr [r15 + BUFSZ + rcx]   // set1[i]
    mov     r10, rcx                    // j = min(i, len2-1)
    cmp     r10, r8
    jb      1f
    lea     r10, [r8 - 1]
1:
    movzx   eax, byte ptr [r15 + r10]   // set2[j]
    mov     [r14 + r9], al              // map[set1[i]] = set2[j]
    inc     rcx
    jmp     .mp

.build_delete:
    cmp     r12, 1
    jl      .usage
    mov     rdi, [r13]
    lea     rsi, [r15 + BUFSZ]
    call    expand_set
    mov     rbx, rax
    xor     rcx, rcx
.del:
    cmp     rcx, rbx
    jae     .run
    movzx   r9, byte ptr [r15 + BUFSZ + rcx]
    mov     byte ptr [r14 + 256 + r9], 1
    inc     rcx
    jmp     .del

.run:
    // Transform stdin -> stdout, block by block. in at r15, out at r15+BUFSZ.
.rd:
    mov     rdi, STDIN
    mov     rsi, r15
    mov     rdx, BUFSZ
    call    uolt_read
    test    rax, rax
    jle     .done
    mov     r12, rax                    // bytes in
    xor     rbx, rbx                    // in index
    xor     r13, r13                    // out length
.tx:
    cmp     rbx, r12
    jae     .flush
    movzx   r9, byte ptr [r15 + rbx]
    cmp     qword ptr [rbp + LOC_DEL], 0
    je      .tx_map
    cmp     byte ptr [r14 + 256 + r9], 0
    jne     .tx_skip                    // deleted
    mov     al, r9b
    jmp     .tx_emit
.tx_map:
    movzx   eax, byte ptr [r14 + r9]    // translated byte
.tx_emit:
    mov     [r15 + BUFSZ + r13], al
    inc     r13
.tx_skip:
    inc     rbx
    jmp     .tx
.flush:
    test    r13, r13
    jz      .rd
    mov     rdi, STDOUT
    lea     rsi, [r15 + BUFSZ]
    mov     rdx, r13
    call    uolt_write
    jmp     .rd
.done:
    xor     eax, eax
    jmp     .ret
.usage:
    lea     rdi, [rip + err_usage]
    call    err_puts
    mov     eax, 1
.ret:
    add     rsp, 2*BUFSZ + 1024 + 64
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

// expand_set(rdi = ASCIZ set, rsi = dest buffer) -> rax = count (capped at 256).
// Expands ranges like a-z into individual bytes.
expand_set:
    xor     rax, rax
.xs_loop:
    movzx   ecx, byte ptr [rdi]
    test    cl, cl
    jz      .xs_done
    cmp     rax, 256
    jae     .xs_done
    cmp     byte ptr [rdi + 1], '-'
    jne     .xs_lit
    movzx   edx, byte ptr [rdi + 2]
    test    dl, dl
    jz      .xs_lit                     // '-' at end -> literal '-'
    // range cl..dl
.xs_range:
    cmp     rax, 256
    jae     .xs_range_done
    mov     [rsi + rax], cl
    inc     rax
    cmp     cl, dl
    jae     .xs_range_done
    inc     cl
    jmp     .xs_range
.xs_range_done:
    add     rdi, 3
    jmp     .xs_loop
.xs_lit:
    mov     [rsi + rax], cl
    inc     rax
    inc     rdi
    jmp     .xs_loop
.xs_done:
    ret

err_puts:
    mov     r10, rdi
    call    uolt_strlen
    mov     rdx, rax
    mov     rsi, r10
    mov     rdi, STDERR
    jmp     uolt_write

err_usage: .asciz "uolt-tr: usage: tr set1 set2 | tr -d set1\n"
