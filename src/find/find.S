// src/find/find.S - the `find` utility (recursive listing).
//
// find [path...] [-type f|d]: print each path at or under the given starting
// points (default "."), one per line, descending into directories. -type f
// restricts the output to regular files, -type d to directories. The -name glob
// filter and the many other predicates/actions are out of scope in v1.
//
// The walk descends with recursion: each directory level keeps its own getdents
// buffer on the stack so it survives the recursion into child entries, while a
// single path buffer (r15) is grown by appending "/name" and truncated on return
// (no heap, Principle IV). A directory is detected by opening with O_DIRECTORY:
// ENOTDIR marks a file. Depth is bounded by the process stack.
//
// Called as uolt_main(argc in rdi, argv in rsi) by the per-OS entry shim.
//
// Global registers across the walk: r15 = path buffer, r14 = type filter
//   (0 = any, 'f', or 'd'). Per-level (in find_entry): rbx = path length,
//   r12 = dir fd; the directory buffer, batch length, and scan position live in
//   the level's own stack frame.

#include "uolt.inc"

.set STDOUT,   1
.set STDERR,   2
.set ENOTDIR,  20
.set PATHMAX,  4096
.set DBUFSZ,   4096

.set LOC_NAME, -48              // -name glob pattern (0 = none)

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
    sub     rsp, PATHMAX + 32
    mov     r15, rsp
    xor     r14, r14                    // type filter (0 = any)
    mov     qword ptr [rbp + LOC_NAME], 0       // -name pattern (0 = none)

    mov     r12, rdi
    dec     r12                         // operand count
    lea     r13, [rsi + 8]

    // Strip trailing "-type f|d" and "-name PATTERN" predicates (any order), so
    // the remaining leading operands are the start paths.
.strip:
    cmp     r12, 2
    jl      .paths
    mov     rax, [r13 + r12*8 - 16]     // second-to-last operand
    lea     rdi, [rip + opt_type]
    mov     rsi, rax
    call    .streq
    test    rax, rax
    jnz     .strip_type
    lea     rdi, [rip + opt_name]
    mov     rsi, [r13 + r12*8 - 16]
    call    .streq
    test    rax, rax
    jnz     .strip_name
    jmp     .paths
.strip_type:
    mov     rax, [r13 + r12*8 - 8]      // last operand: f or d
    movzx   rcx, byte ptr [rax]
    cmp     cl, 'f'
    je      1f
    cmp     cl, 'd'
    jne     .paths
1:
    cmp     byte ptr [rax + 1], 0
    jne     .paths
    mov     r14, rcx
    sub     r12, 2
    jmp     .strip
.strip_name:
    mov     rax, [r13 + r12*8 - 8]      // the glob pattern
    mov     [rbp + LOC_NAME], rax
    sub     r12, 2
    jmp     .strip

.paths:
    test    r12, r12
    jnz     .ploop
    // no path operands: walk "."
    mov     byte ptr [r15], '.'
    mov     rdi, 1
    xor     rsi, rsi                    // DT_UNKNOWN: probe by opening
    call    find_entry
    jmp     .fin
.ploop:
    test    r12, r12
    jz      .fin
    mov     rsi, [r13]                  // copy the operand into the path buffer
    mov     rdi, r15
    call    .copy_str                   // -> rax = length
    mov     rdi, rax
    xor     rsi, rsi                    // DT_UNKNOWN for command-line operands
    call    find_entry
    add     r13, 8
    dec     r12
    jmp     .ploop

.fin:
    xor     eax, eax
    add     rsp, PATHMAX + 32
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

// find_entry(rdi = path length, rsi = d_type hint): print the path (if it passes
// -type) and, if it is a directory, recurse into its entries. The d_type hint
// (from the parent's getdents record) classifies the entry without following
// symlinks; DT_UNKNOWN (command-line operands, or filesystems that do not report
// a type) falls back to opening the path. Preserves rbx (this level's length).
find_entry:
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     byte ptr [r15 + rbx], 0
    cmp     rsi, DT_DIR
    je      .fe_opendir
    cmp     rsi, DT_UNKNOWN
    je      .fe_probe
    // a known non-directory: print with its type char, no descent
    mov     dl, '?'
    cmp     rsi, DT_REG
    jne     1f
    mov     dl, 'f'
1:
    cmp     rsi, DT_LNK
    jne     2f
    mov     dl, 'l'
2:
    call    print_cur
    jmp     .fe_ret
.fe_probe:
    mov     rdi, r15
    call    uolt_opendir
    test    rax, rax
    js      .fe_probe_file
    mov     r12, rax
    jmp     .fe_have_dir
.fe_probe_file:
    cmp     rax, -ENOTDIR
    jne     .fe_ret                     // ENOENT/other -> do not print
    mov     dl, 'f'
    call    print_cur
    jmp     .fe_ret
.fe_opendir:
    mov     rdi, r15
    call    uolt_opendir
    test    rax, rax
    js      .fe_ret                     // e.g. permission denied: skip
    mov     r12, rax
.fe_have_dir:
    mov     dl, 'd'
    call    print_cur
    sub     rsp, DBUFSZ + 16            // this level's getdents buffer + state
.fe_read:
    mov     rdi, r12
    mov     rsi, rsp
    mov     rdx, DBUFSZ
    call    uolt_getdents
    test    rax, rax
    jle     .fe_endread
    mov     [rsp + DBUFSZ], rax         // batch length
    mov     qword ptr [rsp + DBUFSZ + 8], 0     // scan position
.fe_ent:
    mov     rcx, [rsp + DBUFSZ + 8]
    cmp     rcx, [rsp + DBUFSZ]
    jae     .fe_read
    lea     rsi, [rsp + rcx + DIRENT_NAME_OFF]  // entry name
    movzx   r8, byte ptr [rsp + rcx + DIRENT_TYPE_OFF]   // entry d_type
    // advance the stored position past this record now (survives the recursion)
    movzx   rax, word ptr [rsp + rcx + DIRENT_RECLEN_OFF]
    test    rax, rax
    jz      .fe_read                    // reclen 0 guard
    add     rax, rcx
    mov     [rsp + DBUFSZ + 8], rax
    // skip "." and ".."
    cmp     byte ptr [rsi], '.'
    jne     .fe_do
    cmp     byte ptr [rsi + 1], 0
    je      .fe_ent
    cmp     byte ptr [rsi + 1], '.'
    jne     .fe_do
    cmp     byte ptr [rsi + 2], 0
    je      .fe_ent
.fe_do:
    // append "/name" to the path at [r15 + rbx]
    mov     byte ptr [r15 + rbx], '/'
    lea     rdi, [r15 + rbx + 1]
.fe_cpy:
    mov     al, [rsi]
    mov     [rdi], al
    test    al, al
    jz      .fe_cpydone
    inc     rsi
    inc     rdi
    jmp     .fe_cpy
.fe_cpydone:
    sub     rdi, r15                    // new length
    mov     rsi, r8                     // pass the entry's d_type down
    call    find_entry                  // recurse
    jmp     .fe_ent
.fe_endread:
    add     rsp, DBUFSZ + 16
    mov     rdi, r12
    call    uolt_close
.fe_ret:
    pop     r12
    pop     rbx
    ret

// print_cur(dl = this path's type 'f'/'d'): print the current path (r15, length
// rbx) unless the -type filter rejects it. Preserves rbx/r12/r14/r15.
print_cur:
    test    r14, r14
    jz      .pc_name
    cmp     r14b, dl
    jne     .pc_skip
.pc_name:
    // -name: match the glob against the path's basename
    mov     rax, [rbp + LOC_NAME]
    test    rax, rax
    jz      .pc_go
    mov     rcx, rbx                    // scan back for the last '/'
    lea     rsi, [r15]                  // default basename = whole path
.pc_bn:
    test    rcx, rcx
    jz      .pc_haveb
    dec     rcx
    cmp     byte ptr [r15 + rcx], '/'
    jne     .pc_bn
    lea     rsi, [r15 + rcx + 1]
.pc_haveb:
    mov     rdi, rax                    // pattern
    call    glob
    test    rax, rax
    jz      .pc_skip
.pc_go:
    mov     rdi, STDOUT
    mov     rsi, r15
    mov     rdx, rbx
    call    uolt_write
    mov     rdi, STDOUT
    lea     rsi, [rip + nl_char]
    mov     rdx, 1
    call    uolt_write
.pc_skip:
    ret

// .copy_str(rdi = dst, rsi = src ASCIZ) -> rax = length copied.
.copy_str:
    xor     rax, rax
1:
    mov     cl, [rsi + rax]
    mov     [rdi + rax], cl
    test    cl, cl
    jz      2f
    inc     rax
    jmp     1b
2:
    ret

// .streq(rdi, rsi) -> rax = 1 if the ASCIZ strings are equal, else 0.
.streq:
    xor     rax, rax
1:
    mov     cl, [rdi + rax]
    cmp     cl, [rsi + rax]
    jne     3f
    test    cl, cl
    jz      2f
    inc     rax
    jmp     1b
2:
    mov     rax, 1
    ret
3:
    xor     rax, rax
    ret

// glob(rdi = pattern, rsi = string) -> rax = 1 if the pattern matches the whole
// string. Supports '*' (any run) and '?' (any single char); no character classes.
// Preserves rbx/r12/r13/r14/r15.
glob:
    xor     r8, r8                      // star pattern position (0 = none)
    xor     r9, r9                      // star string position
.gl:
    movzx   eax, byte ptr [rdi]
    test    al, al
    jz      .gl_pend
    cmp     al, '*'
    jne     .gl_lit
    inc     rdi
    mov     r8, rdi                     // remember position after '*'
    mov     r9, rsi
    jmp     .gl
.gl_lit:
    movzx   ecx, byte ptr [rsi]
    test    cl, cl
    jz      .gl_bt
    cmp     al, '?'
    je      .gl_adv
    cmp     al, cl
    jne     .gl_bt
.gl_adv:
    inc     rdi
    inc     rsi
    jmp     .gl
.gl_pend:
    cmp     byte ptr [rsi], 0
    je      .gl_yes
.gl_bt:
    test    r8, r8
    jz      .gl_no
    cmp     byte ptr [r9], 0            // no more string for '*' to absorb
    je      .gl_no
    mov     rdi, r8
    inc     r9
    mov     rsi, r9
    jmp     .gl
.gl_yes:
    mov     rax, 1
    ret
.gl_no:
    xor     rax, rax
    ret

nl_char:  .byte  0x0a
opt_type: .asciz "-type"
opt_name: .asciz "-name"
