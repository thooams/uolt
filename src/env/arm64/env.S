// src/env/arm64/env.S - the `env` utility (aarch64).
//
// env [-i] [-u NAME]... [NAME=VALUE]... [COMMAND [ARG]...]. With no COMMAND,
// print the (modified) environment; with one, execve it. -i empties the env;
// -u removes; NAME=VALUE adds/overrides. A COMMAND without '/' is looked up in
// PATH (default "/usr/bin:/bin"). envp follows argv in memory: argv+(argc+1)*8.
// No heap (Principle IV): the new env array, -u/assignment lists, and the search
// path all live in one stack region. Exit 0 on print, 127 on exec failure, 125
// on a bad option. Mirrors the x86_64 body.
//
// Frame (sp, size 12288): saved regs at [0..64); the arrays+locals region is
// anchored by x25 = sp+128 (a stable base every helper can use, since STP's
// offset range can't reach the region directly). newenv at x25+0.

#include "uolt.inc"

.set STDOUT, 1
.set STDERR, 2

.set UNSET_OFF,  4096           // 512 * 8
.set ASSIGN_OFF, 5120           // + 128 * 8
.set PATH_OFF,   7168           // + 256 * 8 (pathbuf follows)
.set L_IGNORE,   11264
.set L_NU,       11272
.set L_NA,       11280
.set L_ENVP,     11288
.set L_CMDARGV,  11296
.set L_OPTEND,   11304

.text
.globl uolt_main
uolt_main:
    sub     sp, sp, #12288
    stp     x19, x20, [sp, #0]
    stp     x21, x22, [sp, #16]
    stp     x23, x24, [sp, #32]
    stp     x25, x30, [sp, #48]
    add     x25, sp, #128               // region/locals base

    mov     x19, x1                     // argv
    mov     x20, x0                     // argc
    add     x9, x0, #1                  // envp = argv + (argc+1)*8
    add     x9, x19, x9, lsl #3
    str     x9, [x25, #L_ENVP]
    str     xzr, [x25, #L_IGNORE]
    str     xzr, [x25, #L_NU]
    str     xzr, [x25, #L_NA]
    str     xzr, [x25, #L_CMDARGV]
    str     xzr, [x25, #L_OPTEND]

    // --- Parse operands ---
    mov     x21, #1                     // i
.Lp_loop:
    cmp     x21, x20
    b.hs    .Lp_done
    ldr     x2, [x19, x21, lsl #3]      // arg
    ldr     x9, [x25, #L_OPTEND]
    cmp     x9, #1
    b.eq    .Lp_operand
    ldrb    w9, [x2]
    cmp     w9, #'-'
    b.ne    .Lp_operand
    ldrb    w9, [x2, #1]
    cbz     w9, .Lp_dash                // "-" alone == -i
    cmp     w9, #'i'
    b.eq    .Lp_i
    cmp     w9, #'u'
    b.eq    .Lp_u
    cmp     w9, #'-'
    b.eq    .Lp_dd
    b       .Lp_badopt
.Lp_i:
    ldrb    w9, [x2, #2]
    cbnz    w9, .Lp_badopt
    mov     x9, #1
    str     x9, [x25, #L_IGNORE]
    add     x21, x21, #1
    b       .Lp_loop
.Lp_dash:
    mov     x9, #1
    str     x9, [x25, #L_IGNORE]
    add     x21, x21, #1
    b       .Lp_loop
.Lp_dd:
    ldrb    w9, [x2, #2]
    cbnz    w9, .Lp_badopt
    mov     x9, #1
    str     x9, [x25, #L_OPTEND]
    add     x21, x21, #1
    b       .Lp_loop
.Lp_u:
    add     x3, x2, #2                  // "-uNAME" attached, or "-u" then next arg
    ldrb    w9, [x3]
    cbnz    w9, .Lp_uhave
    add     x21, x21, #1
    cmp     x21, x20
    b.hs    .Lp_done
    ldr     x3, [x19, x21, lsl #3]
.Lp_uhave:
    ldr     x9, [x25, #L_NU]
    mov     x11, #UNSET_OFF
    add     x10, x25, x11
    str     x3, [x10, x9, lsl #3]
    add     x9, x9, #1
    str     x9, [x25, #L_NU]
    add     x21, x21, #1
    b       .Lp_loop
.Lp_operand:
    mov     x0, x2                      // assignment (has '=') or command
    bl      has_eq
    cbz     x0, .Lp_command
    ldr     x2, [x19, x21, lsl #3]
    ldr     x9, [x25, #L_NA]
    mov     x11, #ASSIGN_OFF
    add     x10, x25, x11
    str     x2, [x10, x9, lsl #3]
    add     x9, x9, #1
    str     x9, [x25, #L_NA]
    add     x21, x21, #1
    b       .Lp_loop
.Lp_command:
    add     x9, x19, x21, lsl #3        // &argv[command index]
    str     x9, [x25, #L_CMDARGV]
.Lp_done:

    // --- Build the new environment into newenv[] (base x25) ---
    mov     x22, #0                     // k = count
    ldr     x9, [x25, #L_IGNORE]
    cmp     x9, #1
    b.eq    .Lb_assigns
    ldr     x23, [x25, #L_ENVP]         // inherited env walk
.Lb_inh:
    ldr     x0, [x23]
    cbz     x0, .Lb_assigns
    bl      is_suppressed               // 1 if unset or overridden
    cbnz    x0, .Lb_inh_next
    ldr     x0, [x23]
    str     x0, [x25, x22, lsl #3]
    add     x22, x22, #1
.Lb_inh_next:
    add     x23, x23, #8
    b       .Lb_inh
.Lb_assigns:
    mov     x9, #0
.Lb_as:
    ldr     x10, [x25, #L_NA]
    cmp     x9, x10
    b.hs    .Lb_null
    mov     x12, #ASSIGN_OFF
    add     x11, x25, x12
    ldr     x0, [x11, x9, lsl #3]
    str     x0, [x25, x22, lsl #3]
    add     x22, x22, #1
    add     x9, x9, #1
    b       .Lb_as
.Lb_null:
    str     xzr, [x25, x22, lsl #3]     // NULL-terminate

    // --- Run the command, or print the environment ---
    ldr     x9, [x25, #L_CMDARGV]
    cbnz    x9, .Lexec

    mov     x21, #0
.Lpr:
    ldr     x0, [x25, x21, lsl #3]
    cbz     x0, .Lpr_done
    bl      put_line
    add     x21, x21, #1
    b       .Lpr
.Lpr_done:
    mov     x0, #0
    b       .Lret

.Lexec:
    ldr     x23, [x25, #L_CMDARGV]      // argv for execve (already NULL-terminated)
    ldr     x24, [x23]                  // command string
    mov     x0, x24
    bl      has_slash
    cbz     x0, .Lexec_path
    mov     x0, x24                     // command contains '/': exec directly
    mov     x1, x23
    mov     x2, x25                     // envp = newenv base
    bl      uolt_execve
    b       .Lexec_fail
.Lexec_path:
    mov     x9, #0                      // find PATH= in the new environment
.Lep_find:
    ldr     x0, [x25, x9, lsl #3]
    cbz     x0, .Lep_default
    mov     x10, x9                     // save idx across is_path
    bl      is_path
    cbnz    x0, .Lep_got
    add     x9, x10, #1
    b       .Lep_find
.Lep_got:
    add     x11, x25, x10, lsl #3
    ldr     x0, [x11]
    add     x22, x0, #5                 // value after "PATH="
    b       .Lep_iter
.Lep_default:
    adr     x22, default_path
.Lep_iter:
.Lep_dir:
    mov     x6, x22                     // dir start
.Lep_scan:
    ldrb    w9, [x22]
    cbz     w9, .Lep_lastdir
    cmp     w9, #':'
    b.eq    .Lep_havedir
    add     x22, x22, #1
    b       .Lep_scan
.Lep_havedir:
    sub     x7, x22, x6                 // dir length
    add     x22, x22, #1               // past ':'
    bl      try_dir                     // returns only on failure
    b       .Lep_dir
.Lep_lastdir:
    sub     x7, x22, x6
    bl      try_dir
.Lexec_fail:
    adr     x0, err_pre
    bl      err_puts
    mov     x0, x24
    bl      err_puts
    adr     x0, err_nf
    bl      err_puts
    mov     x0, #127
    b       .Lret
.Lp_badopt:
    adr     x0, err_usage
    bl      err_puts
    mov     x0, #125
.Lret:
    ldp     x19, x20, [sp, #0]
    ldp     x21, x22, [sp, #16]
    ldp     x23, x24, [sp, #32]
    ldp     x25, x30, [sp, #48]
    add     sp, sp, #12288
    ret

// try_dir(x6 = dir start, x7 = dir length): build "dir/command" in pathbuf and
// execve it with x23=argv, x25=envp. Returns only if the exec failed.
try_dir:
    stp     x29, x30, [sp, #-16]!
    mov     x13, #PATH_OFF
    add     x9, x25, x13                // dst
    cbnz    x7, .Ltd_copy
    mov     w10, #'.'                   // empty dir -> current directory
    strb    w10, [x9], #1
    b       .Ltd_slash
.Ltd_copy:
    mov     x11, #0
.Ltd_cd:
    cmp     x11, x7
    b.hs    .Ltd_slash
    ldrb    w10, [x6, x11]
    strb    w10, [x9], #1
    add     x11, x11, #1
    b       .Ltd_cd
.Ltd_slash:
    mov     w10, #'/'
    strb    w10, [x9], #1
    mov     x12, x24                    // append the command
.Ltd_cc:
    ldrb    w10, [x12]
    strb    w10, [x9]
    cbz     w10, .Ltd_exec
    add     x12, x12, #1
    add     x9, x9, #1
    b       .Ltd_cc
.Ltd_exec:
    mov     x9, #PATH_OFF
    add     x0, x25, x9
    mov     x1, x23
    mov     x2, x25
    bl      uolt_execve
    ldp     x29, x30, [sp], #16
    ret                                 // only reached on failure

// is_suppressed(x0 = "NAME=value") -> x0 = 1 if NAME matches a -u name or an
// assignment name, else 0. x5/x6 survive key_match; saves lr.
is_suppressed:
    stp     x29, x30, [sp, #-16]!
    mov     x6, x0                      // NAME ptr
    mov     x5, #0
.Liss_u:
    ldr     x9, [x25, #L_NU]
    cmp     x5, x9
    b.hs    .Liss_a
    mov     x0, x6
    mov     x11, #UNSET_OFF
    add     x10, x25, x11
    ldr     x1, [x10, x5, lsl #3]
    bl      key_match
    cbnz    x0, .Liss_yes
    add     x5, x5, #1
    b       .Liss_u
.Liss_a:
    mov     x5, #0
.Liss_al:
    ldr     x9, [x25, #L_NA]
    cmp     x5, x9
    b.hs    .Liss_no
    mov     x0, x6
    mov     x11, #ASSIGN_OFF
    add     x10, x25, x11
    ldr     x1, [x10, x5, lsl #3]
    bl      key_match
    cbnz    x0, .Liss_yes
    add     x5, x5, #1
    b       .Liss_al
.Liss_no:
    mov     x0, #0
    ldp     x29, x30, [sp], #16
    ret
.Liss_yes:
    mov     x0, #1
    ldp     x29, x30, [sp], #16
    ret

// key_match(x0 = a, x1 = b) -> x0 = 1 if the NAME parts (up to '=' or NUL) match.
key_match:
    mov     x2, #0
.km:
    ldrb    w3, [x0, x2]
    ldrb    w4, [x1, x2]
    cmp     w3, #'='
    b.eq    .km_aend
    cbz     w3, .km_aend
    cmp     w4, #'='
    b.eq    .km_no
    cbz     w4, .km_no
    cmp     w3, w4
    b.ne    .km_no
    add     x2, x2, #1
    b       .km
.km_aend:
    cmp     w4, #'='
    b.eq    .km_yes
    cbz     w4, .km_yes
.km_no:
    mov     x0, #0
    ret
.km_yes:
    mov     x0, #1
    ret

// has_eq(x0 = str) -> x0 = 1 if it contains '='.
has_eq:
    mov     x1, #0
1:
    ldrb    w2, [x0, x1]
    cbz     w2, 2f
    cmp     w2, #'='
    b.eq    3f
    add     x1, x1, #1
    b       1b
2:
    mov     x0, #0
    ret
3:
    mov     x0, #1
    ret

// has_slash(x0 = str) -> x0 = 1 if it contains '/'.
has_slash:
    mov     x1, #0
1:
    ldrb    w2, [x0, x1]
    cbz     w2, 2f
    cmp     w2, #'/'
    b.eq    3f
    add     x1, x1, #1
    b       1b
2:
    mov     x0, #0
    ret
3:
    mov     x0, #1
    ret

// is_path(x0 = str) -> x0 = 1 if it begins with "PATH=".
is_path:
    ldrb    w1, [x0]
    cmp     w1, #'P'
    b.ne    1f
    ldrb    w1, [x0, #1]
    cmp     w1, #'A'
    b.ne    1f
    ldrb    w1, [x0, #2]
    cmp     w1, #'T'
    b.ne    1f
    ldrb    w1, [x0, #3]
    cmp     w1, #'H'
    b.ne    1f
    ldrb    w1, [x0, #4]
    cmp     w1, #'='
    b.ne    1f
    mov     x0, #1
    ret
1:
    mov     x0, #0
    ret

// put_line(x0 = ASCIZ): write the string and a newline to stdout. Saves lr.
put_line:
    stp     x29, x30, [sp, #-16]!
    mov     x3, x0
    bl      uolt_strlen
    mov     x2, x0
    mov     x1, x3
    mov     x0, #STDOUT
    bl      uolt_write
    mov     x0, #STDOUT
    adr     x1, nl_char
    mov     x2, #1
    bl      uolt_write
    ldp     x29, x30, [sp], #16
    ret

// err_puts(x0 = ASCIZ) -> stderr. Saves lr.
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

nl_char:      .byte  0x0a
default_path: .asciz "/usr/bin:/bin"
err_pre:      .asciz "uolt-env: "
err_nf:       .asciz ": No such file or directory\n"
err_usage:    .asciz "uolt-env: usage: env [-i] [-u NAME]... [NAME=VALUE]... [command [arg]...]\n"
