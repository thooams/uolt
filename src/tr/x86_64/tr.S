// src/tr/tr.S - the `tr` utility (translate / delete).
//
// tr set1 set2   translate bytes in set1 to the matching byte of set2
// tr -d set1     delete bytes in set1
// tr -s set1     squeeze repeated bytes in set1 to one
//
// -c (or -C) complements set1: the operation applies to every byte NOT listed in
// set1. Options combine: `tr -cd set1` deletes everything except set1, `tr -cs
// set1` squeezes runs outside set1, `tr -c set1 set2` maps every byte outside
// set1 to set2. Each set is a sequence of literal bytes and ranges (e.g. a-z).
// For translation a byte in set1 is mapped to the byte at the same index in set2,
// or to set2's last byte if set2 is shorter (the common tr behavior). Backslash
// escapes are out of scope in v1.
//
// A 256-entry translate table, a 256-entry delete flag, and a 256-entry squeeze
// flag are built on the stack (no heap, Principle IV). Input is transformed block
// by block through a 64 KB buffer; the last output byte is carried across blocks
// so squeeze runs span block boundaries.
//
// Called as uolt_main(argc in rdi, argv in rsi) by the per-OS entry shim.
//
// Global registers: r15 = I/O buffer; r14 = tables (256 map + 256 delete + 256
//   squeeze). Stack locals [-48] = -d, [-56] = -s, [-64] = last output byte.

#include "uolt.inc"

.set STDIN,  0
.set STDOUT, 1
.set STDERR, 2
.set BUFSZ,  65536

.set LOC_DEL,  -48
.set LOC_SQ,   -56
.set LOC_PREV, -64
.set LOC_C,    -72

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
    mov     qword ptr [rbp + LOC_SQ], 0
    mov     qword ptr [rbp + LOC_PREV], -1
    mov     qword ptr [rbp + LOC_C], 0

    mov     r12, rdi
    dec     r12
    lea     r13, [rsi + 8]

    // Leading options: any token like -d, -s, -ds, -sd (letters d and s only).
.opt:
    test    r12, r12
    jz      .init
    mov     rbx, [r13]
    cmp     byte ptr [rbx], '-'
    jne     .init
    cmp     byte ptr [rbx + 1], 0
    je      .init                       // "-" is an operand (unused, but not a flag)
    cmp     byte ptr [rbx + 1], '-'
    je      .ddash
    lea     rcx, [rbx + 1]              // validate every letter is d/s/c/C
    mov     rdi, rcx
.ov:
    movzx   eax, byte ptr [rdi]
    test    al, al
    jz      .oapply
    cmp     al, 'd'
    je      1f
    cmp     al, 's'
    je      1f
    cmp     al, 'c'
    je      1f
    cmp     al, 'C'
    je      1f
    jmp     .init                       // unknown letter -> treat token as a set
1:
    inc     rdi
    jmp     .ov
.oapply:
    lea     rdi, [rbx + 1]
.oa:
    movzx   eax, byte ptr [rdi]
    test    al, al
    jz      .odone
    cmp     al, 'd'
    jne     2f
    mov     qword ptr [rbp + LOC_DEL], 1
2:
    cmp     al, 's'
    jne     3f
    mov     qword ptr [rbp + LOC_SQ], 1
3:
    cmp     al, 'c'
    je      4f
    cmp     al, 'C'
    jne     5f
4:
    mov     qword ptr [rbp + LOC_C], 1  // -c / -C: complement set1
5:
    inc     rdi
    jmp     .oa
.odone:
    add     r13, 8
    dec     r12
    jmp     .opt
.ddash:
    cmp     byte ptr [rbx + 2], 0
    jne     .init
    add     r13, 8
    dec     r12
.init:
    // Build an identity map, a clear delete table, and a clear squeeze table.
    xor     rcx, rcx
.id:
    mov     al, cl
    mov     [r14 + rcx], al             // map[c] = c
    mov     byte ptr [r14 + 256 + rcx], 0
    mov     byte ptr [r14 + 512 + rcx], 0
    inc     rcx
    cmp     rcx, 256
    jne     .id

    cmp     qword ptr [rbp + LOC_DEL], 0
    jne     .build_delete

    // No delete. With two sets, translate set1 -> set2; with one set, -s alone
    // is squeeze-only (identity map). The squeeze set (when -s) is the last set.
    cmp     r12, 2
    jge     .translate2
    cmp     r12, 1
    jl      .usage
    cmp     qword ptr [rbp + LOC_SQ], 0
    je      .usage                      // one set and no -s: not a valid tr
    // squeeze-only: mark sq from set1
    mov     rdi, [r13]
    lea     rsi, [r15 + BUFSZ]
    call    expand_set
    mov     rbx, rax
    lea     r10, [r15 + BUFSZ]
    call    .mark_sq                    // (r10 = bytes, rbx = count)
    cmp     qword ptr [rbp + LOC_C], 0  // -c: squeeze the complement
    je      .run
    xor     rcx, rcx
.sqo_inv:
    xor     byte ptr [r14 + 512 + rcx], 1
    inc     rcx
    cmp     rcx, 256
    jne     .sqo_inv
    jmp     .run
.translate2:
    mov     rdi, [r13]                  // set1 -> expand into out-buffer area
    lea     rsi, [r15 + BUFSZ]
    call    expand_set
    mov     rbx, rax                    // len1
    mov     rdi, [r13 + 8]              // set2 -> expand into I/O buffer
    mov     rsi, r15
    call    expand_set
    mov     r8, rax                     // len2
    test    r8, r8
    jz      .usage
    cmp     qword ptr [rbp + LOC_C], 0
    jne     .translate_c
    // map[set1[i]] = set2[min(i, len2-1)]
    xor     rcx, rcx
.mp:
    cmp     rcx, rbx
    jae     .mp_done
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
.translate_c:
    // -c: map every byte NOT in set1, in ascending order, to set2 (last byte of
    // set2 for all beyond its length). Build set1 membership in in1[] at r14+768.
    xor     rcx, rcx
.tc_clr:
    mov     byte ptr [r14 + 768 + rcx], 0
    inc     rcx
    cmp     rcx, 256
    jne     .tc_clr
    xor     rcx, rcx
.tc_mark:
    cmp     rcx, rbx
    jae     .tc_map
    movzx   r9, byte ptr [r15 + BUFSZ + rcx]
    mov     byte ptr [r14 + 768 + r9], 1
    inc     rcx
    jmp     .tc_mark
.tc_map:
    xor     rcx, rcx                    // c
    xor     r11, r11                    // k = index among complement bytes
.tc_loop:
    cmp     rcx, 256
    jae     .mp_done
    cmp     byte ptr [r14 + 768 + rcx], 0
    jne     .tc_next                    // c is in set1 -> keep identity map
    mov     r10, r11                    // j = min(k, len2-1)
    cmp     r10, r8
    jb      1f
    lea     r10, [r8 - 1]
1:
    movzx   eax, byte ptr [r15 + r10]
    mov     [r14 + rcx], al
    inc     r11
.tc_next:
    inc     rcx
    jmp     .tc_loop
.mp_done:
    cmp     qword ptr [rbp + LOC_SQ], 0
    je      .run
    mov     rbx, r8                     // squeeze set = set2
    mov     r10, r15
    call    .mark_sq
    jmp     .run

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
    jae     .del_done
    movzx   r9, byte ptr [r15 + BUFSZ + rcx]
    mov     byte ptr [r14 + 256 + r9], 1
    inc     rcx
    jmp     .del
.del_done:
    cmp     qword ptr [rbp + LOC_C], 0  // -c: delete the complement of set1
    je      .del_nc
    xor     rcx, rcx
.del_inv:
    xor     byte ptr [r14 + 256 + rcx], 1
    inc     rcx
    cmp     rcx, 256
    jne     .del_inv
.del_nc:
    // -d with a second set squeezes that set (tr -ds set1 set2).
    cmp     qword ptr [rbp + LOC_SQ], 0
    je      .run
    cmp     r12, 2
    jl      .run
    mov     rdi, [r13 + 8]
    mov     rsi, r15
    call    expand_set
    mov     rbx, rax
    mov     r10, r15
    call    .mark_sq

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
    cmp     qword ptr [rbp + LOC_SQ], 0
    je      .tx_store
    movzx   edx, al                     // squeeze: drop a run of a squeeze-set char
    cmp     byte ptr [r14 + 512 + rdx], 0
    je      .tx_store                    // not in the squeeze set -> always keep
    cmp     rdx, [rbp + LOC_PREV]
    je      .tx_skip                     // same as the previous output byte -> drop
.tx_store:
    mov     [r15 + BUFSZ + r13], al
    inc     r13
    movzx   edx, al
    mov     [rbp + LOC_PREV], rdx
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

// .mark_sq(r10 = expanded byte buffer, rbx = count): set sq[buf[i]] = 1 for each.
// Clobbers rax, rcx, r9.
.mark_sq:
    xor     rcx, rcx
1:
    cmp     rcx, rbx
    jae     2f
    movzx   r9, byte ptr [r10 + rcx]
    mov     byte ptr [r14 + 512 + r9], 1
    inc     rcx
    jmp     1b
2:
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

err_usage: .asciz "uolt-tr: usage: tr [-cs] set1 set2 | tr -[c]d set1 | tr -[c]s set1\n"
