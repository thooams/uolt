// src/chmod/arm64/chmod.S - the POSIX `chmod` utility (aarch64).
//
// chmod MODE file...: change permission bits. MODE is octal (755, 0644) or
// symbolic ([ugoa][+-=][rwxX], comma-separated). For symbolic modes the current
// mode is fetched via stat; X adds execute only for a directory or when some
// execute bit is already set; who-less clauses honor the umask. s/t out of scope.
// A failure -> stderr diagnostic, exit 1, remaining operands still processed.
// Mirrors the x86_64 body.
//
// Callee-saved: x19 = operand count, x20 = &argv walk, x23 = current path.
// Locals off x29. apply_sym is a leaf using x9..x16.

#include "uolt.inc"

.set STDERR, 2
.set LOC_SYM,   48
.set LOC_MODE,  56
.set LOC_STAT,  64
.set LOC_UMASK, 72

.text
.globl uolt_main
uolt_main:
    sub     sp, sp, #96
    mov     x29, sp
    stp     x19, x20, [sp, #0]
    stp     x21, x22, [sp, #16]
    stp     x23, x30, [sp, #32]
    str     xzr, [x29, #LOC_STAT]

    sub     x19, x0, #1                 // operand count
    add     x20, x1, #8                 // &argv[1]

    mov     x0, #0                      // read the umask: umask(0) then restore
    bl      uolt_umask
    str     x0, [x29, #LOC_UMASK]
    ldr     x0, [x29, #LOC_UMASK]
    bl      uolt_umask
    cmp     x19, #2
    b.lt    .Lusage

    ldr     x23, [x20]                  // classify the mode operand
    ldrb    w9, [x23]
    sub     w9, w9, #'0'
    cmp     w9, #7
    b.hi    .Lsymbolic
    // octal
    str     xzr, [x29, #LOC_SYM]
    mov     x10, #0                     // value
    mov     x11, #0                     // digit-seen
.Lpm:
    ldrb    w9, [x23]
    cbz     w9, .Lpm_done
    sub     w9, w9, #'0'
    cmp     w9, #7
    b.hi    .Lbad_mode
    lsl     x10, x10, #3
    add     x10, x10, w9, uxtw
    mov     x11, #1
    add     x23, x23, #1
    b       .Lpm
.Lpm_done:
    cbz     x11, .Lbad_mode
    str     x10, [x29, #LOC_MODE]
    b       .Lfiles
.Lsymbolic:
    str     x23, [x29, #LOC_SYM]
.Lfiles:
    add     x20, x20, #8                // advance past the mode operand
    sub     x19, x19, #1
.Lloop:
    cbz     x19, .Lfin
    ldr     x23, [x20]
    ldr     x9, [x29, #LOC_SYM]
    cbnz    x9, .Lsym_file
    mov     x0, x23                     // octal: chmod(path, mode)
    ldr     x1, [x29, #LOC_MODE]
    bl      uolt_chmod
    cmp     x0, #0
    b.mi    .Ldiag
    b       .Lnext
.Lsym_file:
    mov     x0, x23
    bl      uolt_statmode
    cmp     x0, #0
    b.mi    .Ldiag
    ldr     x1, [x29, #LOC_SYM]         // x0 = current mode
    bl      apply_sym                   // -> x0 = new mode
    and     x0, x0, #07777
    mov     x1, x0
    mov     x0, x23
    bl      uolt_chmod
    cmp     x0, #0
    b.mi    .Ldiag
    b       .Lnext
.Ldiag:
    mov     x9, #1
    str     x9, [x29, #LOC_STAT]
    adr     x0, err_pre
    bl      err_puts
    mov     x0, x23
    bl      err_puts
    adr     x0, err_suf
    bl      err_puts
.Lnext:
    add     x20, x20, #8
    sub     x19, x19, #1
    b       .Lloop
.Lfin:
    ldr     x0, [x29, #LOC_STAT]
    b       .Lret
.Lbad_mode:
    adr     x0, err_mode
    bl      err_puts
    mov     x0, #1
    b       .Lret
.Lusage:
    adr     x0, err_usage
    bl      err_puts
    mov     x0, #1
.Lret:
    ldp     x19, x20, [sp, #0]
    ldp     x21, x22, [sp, #16]
    ldp     x23, x30, [sp, #32]
    add     sp, sp, #96
    ret

// apply_sym(x0 = current mode, x1 = pattern) -> x0 = new mode. Leaf; uses x9..x16.
//   x9 = working mode, x10 = pattern cursor, x11 = who bits (4=u,2=g,1=o),
//   x12 = explicit-who flag, x13 = operator, x14 = perm bits, x15 = X flag,
//   x16 = built permission mask.
apply_sym:
    mov     x9, x0
    mov     x10, x1
.Las_clause:
    ldrb    w2, [x10]
    cbz     w2, .Las_done
    mov     x11, #0                     // who bits
.Las_who:
    ldrb    w2, [x10]
    cmp     w2, #'u'
    b.ne    1f
    orr     x11, x11, #4
    add     x10, x10, #1
    b       .Las_who
1:
    cmp     w2, #'g'
    b.ne    2f
    orr     x11, x11, #2
    add     x10, x10, #1
    b       .Las_who
2:
    cmp     w2, #'o'
    b.ne    3f
    orr     x11, x11, #1
    add     x10, x10, #1
    b       .Las_who
3:
    cmp     w2, #'a'
    b.ne    .Las_op
    orr     x11, x11, #7
    add     x10, x10, #1
    b       .Las_who
.Las_op:
    mov     x12, x11                    // explicit-who flag
    cbnz    x11, 4f
    mov     x11, #7                     // no who -> all
4:
    ldrb    w13, [x10]                  // operator + - =
    add     x10, x10, #1
    mov     x14, #0                     // perm bits
    mov     x15, #0                     // X flag
.Las_perm:
    ldrb    w2, [x10]
    cmp     w2, #'r'
    b.ne    5f
    orr     x14, x14, #4
    add     x10, x10, #1
    b       .Las_perm
5:
    cmp     w2, #'w'
    b.ne    6f
    orr     x14, x14, #2
    add     x10, x10, #1
    b       .Las_perm
6:
    cmp     w2, #'x'
    b.ne    7f
    orr     x14, x14, #1
    add     x10, x10, #1
    b       .Las_perm
7:
    cmp     w2, #'X'
    b.ne    .Las_x
    mov     x15, #1
    add     x10, x10, #1
    b       .Las_perm
.Las_x:
    cbz     x15, .Las_build
    and     x2, x9, #0170000            // X: add x if directory ...
    mov     x3, #0040000
    cmp     x2, x3
    b.eq    .Las_addx
    mov     x3, #0111                   // ... or any execute bit set
    tst     x9, x3
    b.eq    .Las_build
.Las_addx:
    orr     x14, x14, #1
.Las_build:
    mov     x16, #0                     // permission mask across who fields
    tst     x11, #4
    b.eq    8f
    lsl     x2, x14, #6
    orr     x16, x16, x2
8:
    tst     x11, #2
    b.eq    9f
    lsl     x2, x14, #3
    orr     x16, x16, x2
9:
    tst     x11, #1
    b.eq    10f
    orr     x16, x16, x14
10:
    cbnz    x12, 16f                    // explicit who -> umask not applied
    ldr     x2, [x29, #LOC_UMASK]
    mvn     x2, x2
    and     x16, x16, x2
16:
    cmp     w13, #'+'
    b.ne    11f
    orr     x9, x9, x16
    b       .Las_sep
11:
    cmp     w13, #'-'
    b.ne    12f
    mvn     x2, x16
    and     x9, x9, x2
    b       .Las_sep
12:
    cmp     w13, #'='
    b.ne    .Las_sep
    mov     x3, #0                      // clear the who fields' rwx, then set
    tst     x11, #4
    b.eq    13f
    orr     x3, x3, #0700
13:
    tst     x11, #2
    b.eq    14f
    orr     x3, x3, #070
14:
    tst     x11, #1
    b.eq    15f
    orr     x3, x3, #07
15:
    mvn     x3, x3
    and     x9, x9, x3
    orr     x9, x9, x16
.Las_sep:
    ldrb    w2, [x10]
    cbz     w2, .Las_done
    cmp     w2, #','
    b.ne    .Las_sepadv
    add     x10, x10, #1
    b       .Las_clause
.Las_sepadv:
    add     x10, x10, #1
    b       .Las_sep
.Las_done:
    mov     x0, x9
    ret

err_puts:
    stp     x29, x30, [sp, #-16]!
    mov     x3, x0
    bl      uolt_strlen
    mov     x2, x0
    mov     x1, x3
    mov     x0, #STDERR
    bl      uolt_write
    ldp     x29, x30, [sp], #16
    ret

err_usage: .asciz "uolt-chmod: usage: chmod MODE file...\n"
err_mode:  .asciz "uolt-chmod: invalid mode\n"
err_pre:   .asciz "uolt-chmod: "
err_suf:   .asciz ": cannot change mode\n"
