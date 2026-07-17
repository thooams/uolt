// src/find/arm64/find.S - the `find` utility (recursive listing), aarch64.
//
// find [path...] [-maxdepth N] [-type f|d|l] [-name GLOB]: print each path at or
// under the starting points (default "."), one per line, descending into
// directories. -type restricts output; -maxdepth limits descent; -name matches a
// glob against the basename. Mirrors the x86_64 body.
//
// Recursion: each directory level keeps its own getdents buffer in its stack
// frame, so it survives descent into child entries; one path buffer (x19) is grown
// by appending "/name" and truncated on return (no heap, Principle IV). A
// directory is detected by opening with O_DIRECTORY (ENOTDIR marks a file).
//
// Global across the walk: x19 = path buffer, x20 = type filter (0/'f'/'d'/'l').
// Per-level (find_entry): x23 = path length, x24 = dir fd, x25 = depth. Locals off
// x29. main: x21 = &argv walk, x22 = operand count.

#include "uolt.inc"

.set STDOUT,   1
.set STDERR,   2
.set ENOTDIR,  20
.set PATHMAX,  4096
.set DBUFSZ,   4096

.set LOC_NAME, 48              // -name glob (0 = none)
.set LOC_MAXD, 56             // -maxdepth (large = unlimited)
.set DT_UNL,   0x7fffffff

.text
.globl uolt_main
uolt_main:
    sub     sp, sp, #64
    mov     x29, sp
    str     x30, [x29, #0]
    stp     x19, x20, [x29, #16]
    stp     x21, x22, [x29, #32]
    sub     sp, sp, #4096
    sub     sp, sp, #32                // PATHMAX + 32
    mov     x19, sp
    mov     x20, #0                    // type filter (0 = any)
    str     xzr, [x29, #LOC_NAME]
    mov     x9, #DT_UNL
    str     x9, [x29, #LOC_MAXD]
    sub     x22, x0, #1                // operand count
    add     x21, x1, #8                // &argv[1]

    // Strip trailing "-type f|d|l", "-name PATTERN", "-maxdepth N" predicates.
.strip:
    cmp     x22, #2
    b.lt    .paths
    sub     x9, x22, #2
    ldr     x0, [x21, x9, lsl #3]      // second-to-last operand
    adr     x1, opt_type
    bl      .streq
    cbnz    x0, .strip_type
    sub     x9, x22, #2
    ldr     x0, [x21, x9, lsl #3]
    adr     x1, opt_name
    bl      .streq
    cbnz    x0, .strip_name
    sub     x9, x22, #2
    ldr     x0, [x21, x9, lsl #3]
    adr     x1, opt_maxd
    bl      .streq
    cbnz    x0, .strip_maxd
    b       .paths
.strip_type:
    sub     x9, x22, #1
    ldr     x0, [x21, x9, lsl #3]      // last operand: f, d, or l
    ldrb    w1, [x0]
    cmp     w1, #'f'
    b.eq    .st_ok
    cmp     w1, #'d'
    b.eq    .st_ok
    cmp     w1, #'l'
    b.ne    .paths
.st_ok:
    ldrb    w2, [x0, #1]
    cbnz    w2, .paths
    mov     x20, x1                    // type filter
    sub     x22, x22, #2
    b       .strip
.strip_name:
    sub     x9, x22, #1
    ldr     x0, [x21, x9, lsl #3]
    str     x0, [x29, #LOC_NAME]
    sub     x22, x22, #2
    b       .strip
.strip_maxd:
    sub     x9, x22, #1
    ldr     x0, [x21, x9, lsl #3]
    bl      .atoi
    cmp     x0, #0
    b.mi    .paths                     // not a valid number: leave as operand
    str     x0, [x29, #LOC_MAXD]
    sub     x22, x22, #2
    b       .strip

.paths:
    cbnz    x22, .ploop
    mov     w9, #'.'                   // no path operands: walk "."
    strb    w9, [x19]
    mov     x0, #1
    mov     x1, #0                     // DT_UNKNOWN
    mov     x2, #0                     // depth 0
    bl      find_entry
    b       .fin
.ploop:
    cbz     x22, .fin
    ldr     x1, [x21]                  // copy operand into the path buffer
    mov     x0, x19
    bl      .copy_str                  // -> x0 = length
    mov     x1, #0                     // DT_UNKNOWN
    mov     x2, #0
    bl      find_entry
    add     x21, x21, #8
    sub     x22, x22, #1
    b       .ploop

.fin:
    mov     x0, #0
    mov     sp, x29
    ldr     x30, [x29, #0]
    ldp     x19, x20, [x29, #16]
    ldp     x21, x22, [x29, #32]
    add     sp, sp, #64
    ret

// find_entry(x0 = path length, x1 = d_type hint, x2 = depth): print the path (if
// it passes -type/-name) and, if a directory, recurse. x23 = path length, x24 =
// dir fd, x25 = depth. Frame: [0]x23,x24 [16]x25,x30 [32]batch [40]pos
// [48..48+DBUFSZ) dirbuf.
find_entry:
    sub     sp, sp, #4096
    sub     sp, sp, #48
    stp     x23, x24, [sp, #0]
    stp     x25, x30, [sp, #16]
    mov     x25, x2
    mov     x23, x0
    strb    wzr, [x19, x23]            // NUL-terminate the path
    cmp     x1, #DT_DIR
    b.eq    .fe_opendir
    cmp     x1, #DT_UNKNOWN
    b.eq    .fe_probe
    mov     w9, #'?'                   // known non-directory: print with type char
    cmp     x1, #DT_REG
    b.ne    .fe_t1
    mov     w9, #'f'
.fe_t1:
    cmp     x1, #DT_LNK
    b.ne    .fe_t2
    mov     w9, #'l'
.fe_t2:
    mov     x0, x9
    bl      print_cur
    b       .fe_ret
.fe_probe:
    mov     x0, x19
    bl      uolt_opendir
    cmp     x0, #0
    b.mi    .fe_probe_file
    mov     x24, x0
    b       .fe_have_dir
.fe_probe_file:
    cmn     x0, #ENOTDIR
    b.ne    .fe_ret                    // ENOENT/other -> do not print
    mov     x0, #'f'
    bl      print_cur
    b       .fe_ret
.fe_opendir:
    mov     x0, x19
    bl      uolt_opendir
    cmp     x0, #0
    b.mi    .fe_ret                    // permission denied etc: skip
    mov     x24, x0
.fe_have_dir:
    mov     x0, #'d'
    bl      print_cur
    ldr     x9, [x29, #LOC_MAXD]       // at/over -maxdepth: print but do not descend
    cmp     x25, x9
    b.lt    .fe_descend
    mov     x0, x24
    bl      uolt_close
    b       .fe_ret
.fe_descend:
.fe_read:
    mov     x0, x24
    add     x1, sp, #48
    mov     x2, #DBUFSZ
    bl      uolt_getdents
    cmp     x0, #0
    b.le    .fe_endread
    str     x0, [sp, #32]              // batch length
    str     xzr, [sp, #40]             // scan position
.fe_ent:
    ldr     x9, [sp, #40]
    ldr     x10, [sp, #32]
    cmp     x9, x10
    b.hs    .fe_read
    add     x11, sp, #48
    add     x11, x11, x9               // &dirent
    add     x12, x11, #DIRENT_NAME_OFF // entry name
    ldrb    w26, [x11, #DIRENT_TYPE_OFF]   // entry d_type
    ldrh    w13, [x11, #DIRENT_RECLEN_OFF]
    cbz     w13, .fe_read              // reclen 0 guard
    add     x13, x13, x9
    str     x13, [sp, #40]             // advance position (survives recursion)
    ldrb    w13, [x12]
    cmp     w13, #'.'
    b.ne    .fe_do
    ldrb    w13, [x12, #1]
    cbz     w13, .fe_ent
    cmp     w13, #'.'
    b.ne    .fe_do
    ldrb    w13, [x12, #2]
    cbz     w13, .fe_ent
.fe_do:
    mov     w13, #'/'                  // append "/name" at [x19 + x23]
    strb    w13, [x19, x23]
    add     x14, x19, x23
    add     x14, x14, #1
.fe_cpy:
    ldrb    w13, [x12]
    strb    w13, [x14]
    cbz     w13, .fe_cpydone
    add     x12, x12, #1
    add     x14, x14, #1
    b       .fe_cpy
.fe_cpydone:
    sub     x0, x14, x19               // new length
    mov     x1, x26                    // pass the entry's d_type down
    add     x2, x25, #1                // child depth
    bl      find_entry
    b       .fe_ent
.fe_endread:
    mov     x0, x24
    bl      uolt_close
.fe_ret:
    ldp     x23, x24, [sp, #0]
    ldp     x25, x30, [sp, #16]
    add     sp, sp, #4096
    add     sp, sp, #48
    ret

// print_cur(x0 = this path's type char): print the current path (x19, length x23)
// unless -type or -name reject it.
print_cur:
    stp     x29, x30, [sp, #-16]!
    mov     x9, x0                     // type char
    cbz     x20, .pc_name              // filter 0 = any
    cmp     w20, w9
    b.ne    .pc_skip
.pc_name:
    ldr     x10, [x29, #LOC_NAME]
    cbz     x10, .pc_go
    mov     x11, x23                   // scan back for the last '/'
    mov     x1, x19                    // default basename = whole path
.pc_bn:
    cbz     x11, .pc_haveb
    sub     x11, x11, #1
    ldrb    w12, [x19, x11]
    cmp     w12, #'/'
    b.ne    .pc_bn
    add     x1, x19, x11
    add     x1, x1, #1
.pc_haveb:
    mov     x0, x10                    // pattern
    bl      glob
    cbz     x0, .pc_skip
.pc_go:
    mov     x0, #STDOUT
    mov     x1, x19
    mov     x2, x23
    bl      uolt_write
    mov     x0, #STDOUT
    adr     x1, nl_char
    mov     x2, #1
    bl      uolt_write
.pc_skip:
    ldp     x29, x30, [sp], #16
    ret

// .copy_str(x0 = dst, x1 = src ASCIZ) -> x0 = length copied. Leaf.
.copy_str:
    mov     x2, #0
.cs_l:
    ldrb    w3, [x1, x2]
    strb    w3, [x0, x2]
    cbz     w3, .cs_done
    add     x2, x2, #1
    b       .cs_l
.cs_done:
    mov     x0, x2
    ret

// .streq(x0, x1) -> x0 = 1 if the ASCIZ strings are equal, else 0. Leaf.
.streq:
    mov     x2, #0
.se_l:
    ldrb    w3, [x0, x2]
    ldrb    w4, [x1, x2]
    cmp     w3, w4
    b.ne    .se_no
    cbz     w3, .se_yes
    add     x2, x2, #1
    b       .se_l
.se_yes:
    mov     x0, #1
    ret
.se_no:
    mov     x0, #0
    ret

// glob(x0 = pattern, x1 = string) -> x0 = 1 if the pattern matches the whole
// string. '*' any run, '?' any single char. Leaf; touches only x0-x9.
glob:
    mov     x2, x0                     // pattern cursor
    mov     x3, x1                     // string cursor
    mov     x8, #0                     // star pattern pos (0 = none)
    mov     x9, #0                     // star string pos
.gl:
    ldrb    w4, [x2]
    cbz     w4, .gl_pend
    cmp     w4, #'*'
    b.ne    .gl_lit
    add     x2, x2, #1
    mov     x8, x2                     // position after '*'
    mov     x9, x3
    b       .gl
.gl_lit:
    ldrb    w5, [x3]
    cbz     w5, .gl_bt
    cmp     w4, #'?'
    b.eq    .gl_adv
    cmp     w4, w5
    b.ne    .gl_bt
.gl_adv:
    add     x2, x2, #1
    add     x3, x3, #1
    b       .gl
.gl_pend:
    ldrb    w5, [x3]
    cbz     w5, .gl_yes
.gl_bt:
    cbz     x8, .gl_no
    ldrb    w5, [x9]
    cbz     w5, .gl_no                 // no more string for '*' to absorb
    mov     x2, x8
    add     x9, x9, #1
    mov     x3, x9
    b       .gl
.gl_yes:
    mov     x0, #1
    ret
.gl_no:
    mov     x0, #0
    ret

// .atoi(x0 = ASCIZ) -> x0 = value >= 0, or -1 if empty or non-digit. Leaf.
.atoi:
    ldrb    w1, [x0]
    cbz     w1, .ai_err
    mov     x2, x0
    mov     x0, #0
.ai_lp:
    ldrb    w1, [x2]
    cbz     w1, .ai_ok
    sub     w1, w1, #'0'
    cmp     w1, #9
    b.hi    .ai_err
    mov     x3, #10
    mul     x0, x0, x3
    add     x0, x0, w1, uxtw
    add     x2, x2, #1
    b       .ai_lp
.ai_ok:
    ret
.ai_err:
    mov     x0, #-1
    ret

nl_char:  .byte  0x0a
opt_type: .asciz "-type"
opt_name: .asciz "-name"
opt_maxd: .asciz "-maxdepth"
