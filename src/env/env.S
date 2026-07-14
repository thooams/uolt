// src/env/env.S - the `env` utility.
//
// env [-i] [-u NAME]... [NAME=VALUE]... [COMMAND [ARG]...]
//
// With no COMMAND, print the (possibly modified) environment, one "NAME=value"
// per line. With a COMMAND, run it with that environment via execve. -i starts
// from an empty environment; -u NAME removes a variable; NAME=VALUE adds or
// overrides one (an override also drops the inherited entry of the same name).
// When COMMAND contains no '/', it is looked up in the resulting PATH (or the
// default "/usr/bin:/bin").
//
// The environment array follows argv in memory: after argv[argc] (the NULL
// terminator) come the environment pointers, NULL-terminated, so envp is
// argv + (argc + 1) * 8 on both Linux and macOS. No heap (Principle IV): the new
// environment array, the -u / assignment lists, and the PATH-search path buffer
// all live in one stack region; every entry is a pointer into argv or the
// inherited environment (no string copies except the search path).
//
// Exit status: 0 on a successful print; a failed exec exits 127 (not found);
// an unknown option exits 125.
//
// Called as uolt_main(argc in rdi, argv in rsi) by the per-OS entry shim.

#include "uolt.inc"

.set STDOUT, 1
.set STDERR, 2
.set ENOENT,  2
.set ENOTDIR, 20

// Stack region (base in r15): newenv[512], unsets[128], assigns[256], pathbuf.
.set UNSET_OFF,  4096           // 512 * 8
.set ASSIGN_OFF, 5120           // + 128 * 8
.set PATH_OFF,   7168           // + 256 * 8
.set REGION,     11264          // + 4096 (pathbuf)

.set LOC_IGNORE,  -48
.set LOC_NU,      -56           // number of -u names
.set LOC_NA,      -64           // number of assignments
.set LOC_ENVP,    -72           // inherited environment pointer
.set LOC_CMDARGV, -80           // &argv[command index], or 0
.set LOC_OPTEND,  -88           // 1 after "--"
.set LOC_ARGC,    -96
.set LOC_ARGV,    -104

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
    sub     rsp, REGION + 128
    mov     r15, rsp

    mov     [rbp + LOC_ARGC], rdi
    mov     [rbp + LOC_ARGV], rsi
    lea     rax, [rsi + rdi*8 + 8]      // envp = argv + (argc+1)*8
    mov     [rbp + LOC_ENVP], rax
    mov     qword ptr [rbp + LOC_IGNORE], 0
    mov     qword ptr [rbp + LOC_NU], 0
    mov     qword ptr [rbp + LOC_NA], 0
    mov     qword ptr [rbp + LOC_CMDARGV], 0
    mov     qword ptr [rbp + LOC_OPTEND], 0

    // --- Parse operands ---
    mov     r12, rsi                    // argv
    mov     r13, rdi                    // argc
    mov     rbx, 1                      // i
.p_loop:
    cmp     rbx, r13
    jae     .p_done
    mov     rax, [r12 + rbx*8]
    cmp     qword ptr [rbp + LOC_OPTEND], 1
    je      .p_operand
    cmp     byte ptr [rax], '-'
    jne     .p_operand
    cmp     byte ptr [rax + 1], 0
    je      .p_dash                     // "-" alone == -i
    cmp     byte ptr [rax + 1], 'i'
    je      .p_i
    cmp     byte ptr [rax + 1], 'u'
    je      .p_u
    cmp     byte ptr [rax + 1], '-'
    je      .p_dd
    jmp     .p_badopt
.p_i:
    cmp     byte ptr [rax + 2], 0
    jne     .p_badopt
    mov     qword ptr [rbp + LOC_IGNORE], 1
    inc     rbx
    jmp     .p_loop
.p_dash:
    mov     qword ptr [rbp + LOC_IGNORE], 1
    inc     rbx
    jmp     .p_loop
.p_dd:
    cmp     byte ptr [rax + 2], 0
    jne     .p_badopt
    mov     qword ptr [rbp + LOC_OPTEND], 1
    inc     rbx
    jmp     .p_loop
.p_u:
    lea     rdi, [rax + 2]              // "-uNAME" attached, or "-u" then next arg
    cmp     byte ptr [rdi], 0
    jne     .p_uhave
    inc     rbx
    cmp     rbx, r13
    jae     .p_done
    mov     rdi, [r12 + rbx*8]
.p_uhave:
    mov     rcx, [rbp + LOC_NU]
    mov     [r15 + UNSET_OFF + rcx*8], rdi
    inc     rcx
    mov     [rbp + LOC_NU], rcx
    inc     rbx
    jmp     .p_loop
.p_operand:
    mov     rdi, rax                    // assignment (has '=') or command
    call    has_eq
    test    rax, rax
    jz      .p_command
    mov     rax, [r12 + rbx*8]
    mov     rcx, [rbp + LOC_NA]
    mov     [r15 + ASSIGN_OFF + rcx*8], rax
    inc     rcx
    mov     [rbp + LOC_NA], rcx
    inc     rbx
    jmp     .p_loop
.p_command:
    lea     rax, [r12 + rbx*8]          // &argv[command index]
    mov     [rbp + LOC_CMDARGV], rax
.p_done:

    // --- Build the new environment into newenv[] (base r15) ---
    xor     r14, r14                    // k = count
    cmp     qword ptr [rbp + LOC_IGNORE], 1
    je      .b_assigns
    mov     r13, [rbp + LOC_ENVP]
.b_inh:
    mov     rax, [r13]
    test    rax, rax
    jz      .b_assigns
    mov     rdi, rax
    call    is_suppressed               // 1 if unset or overridden
    test    rax, rax
    jnz     .b_inh_next
    mov     rax, [r13]
    mov     [r15 + r14*8], rax
    inc     r14
.b_inh_next:
    add     r13, 8
    jmp     .b_inh
.b_assigns:
    xor     rcx, rcx
.b_as:
    cmp     rcx, [rbp + LOC_NA]
    jae     .b_null
    mov     rax, [r15 + ASSIGN_OFF + rcx*8]
    mov     [r15 + r14*8], rax
    inc     r14
    inc     rcx
    jmp     .b_as
.b_null:
    mov     qword ptr [r15 + r14*8], 0  // NULL-terminate

    // --- Run the command, or print the environment ---
    cmp     qword ptr [rbp + LOC_CMDARGV], 0
    jne     .exec

    xor     rbx, rbx
.pr:
    mov     rax, [r15 + rbx*8]
    test    rax, rax
    jz      .pr_done
    mov     rdi, rax
    call    put_line
    inc     rbx
    jmp     .pr
.pr_done:
    xor     eax, eax
    jmp     .ret

.exec:
    mov     r12, [rbp + LOC_CMDARGV]    // argv for execve (already NULL-terminated)
    mov     r13, [r12]                  // command string
    mov     rdi, r13
    call    has_slash
    test    rax, rax
    jz      .exec_path
    // command contains '/': exec it directly
    mov     rdi, r13
    mov     rsi, r12
    mov     rdx, r15
    call    uolt_execve
    jmp     .exec_fail
.exec_path:
    // find PATH= in the new environment, else use the default
    xor     rcx, rcx
.ep_find:
    mov     rax, [r15 + rcx*8]
    test    rax, rax
    jz      .ep_default
    mov     rdi, rax
    call    is_path
    test    rax, rax
    jnz     .ep_got
    inc     rcx
    jmp     .ep_find
.ep_got:
    mov     rax, [r15 + rcx*8]
    lea     rbx, [rax + 5]              // value after "PATH="
    jmp     .ep_iter
.ep_default:
    lea     rbx, [rip + default_path]
.ep_iter:
    // rbx = PATH cursor; split on ':', try each dir.
.ep_dir:
    mov     r8, rbx                     // dir start
.ep_scan:
    movzx   eax, byte ptr [rbx]
    test    al, al
    je      .ep_lastdir
    cmp     al, ':'
    je      .ep_havedir
    inc     rbx
    jmp     .ep_scan
.ep_havedir:
    mov     r9, rbx
    sub     r9, r8                      // dir length
    inc     rbx                         // past ':'
    call    try_dir                     // returns only on failure
    jmp     .ep_dir
.ep_lastdir:
    mov     r9, rbx
    sub     r9, r8
    call    try_dir
    // no directory worked
.exec_fail:
    lea     rdi, [rip + err_pre]
    call    err_puts
    mov     rdi, r13
    call    err_puts
    lea     rdi, [rip + err_nf]
    call    err_puts
    mov     eax, 127
    jmp     .ret
.p_badopt:
    lea     rdi, [rip + err_usage]
    call    err_puts
    mov     eax, 125
.ret:
    add     rsp, REGION + 128
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

// try_dir(r8 = dir start, r9 = dir length): build "dir/command" in pathbuf and
// execve it with r12=argv, r15=envp. Returns only if the exec failed.
try_dir:
    lea     rdi, [r15 + PATH_OFF]
    test    r9, r9
    jnz     .td_copy
    mov     byte ptr [rdi], '.'         // empty dir -> current directory
    inc     rdi
    jmp     .td_slash
.td_copy:
    xor     rcx, rcx
.td_cd:
    cmp     rcx, r9
    jae     .td_slash
    mov     al, [r8 + rcx]
    mov     [rdi], al
    inc     rdi
    inc     rcx
    jmp     .td_cd
.td_slash:
    mov     byte ptr [rdi], '/'
    inc     rdi
    mov     rsi, r13                    // append the command
.td_cc:
    mov     al, [rsi]
    mov     [rdi], al
    test    al, al
    jz      .td_exec
    inc     rsi
    inc     rdi
    jmp     .td_cc
.td_exec:
    lea     rdi, [r15 + PATH_OFF]
    mov     rsi, r12
    mov     rdx, r15
    call    uolt_execve
    ret                                 // only reached on failure

// is_suppressed(rdi = "NAME=value"): 1 if its NAME matches any -u name or any
// assignment name, else 0. Preserves the caller's r13/r14.
is_suppressed:
    push    rbx
    push    r12
    mov     r12, rdi
    xor     rbx, rbx
.iss_u:
    cmp     rbx, [rbp + LOC_NU]
    jae     .iss_a
    mov     rdi, r12
    mov     rsi, [r15 + UNSET_OFF + rbx*8]
    call    key_match
    test    rax, rax
    jnz     .iss_yes
    inc     rbx
    jmp     .iss_u
.iss_a:
    xor     rbx, rbx
.iss_al:
    cmp     rbx, [rbp + LOC_NA]
    jae     .iss_no
    mov     rdi, r12
    mov     rsi, [r15 + ASSIGN_OFF + rbx*8]
    call    key_match
    test    rax, rax
    jnz     .iss_yes
    inc     rbx
    jmp     .iss_al
.iss_no:
    xor     eax, eax
    pop     r12
    pop     rbx
    ret
.iss_yes:
    mov     eax, 1
    pop     r12
    pop     rbx
    ret

// key_match(rdi = a, rsi = b): 1 if the NAME parts match. A name runs up to '='
// or NUL in either string. Clobbers rax/rcx/rdx.
key_match:
    xor     rcx, rcx
.km:
    mov     al, [rdi + rcx]
    mov     dl, [rsi + rcx]
    cmp     al, '='
    je      .km_aend
    test    al, al
    jz      .km_aend
    cmp     dl, '='
    je      .km_no
    test    dl, dl
    jz      .km_no
    cmp     al, dl
    jne     .km_no
    inc     rcx
    jmp     .km
.km_aend:
    cmp     dl, '='
    je      .km_yes
    test    dl, dl
    jz      .km_yes
.km_no:
    xor     eax, eax
    ret
.km_yes:
    mov     eax, 1
    ret

// has_eq(rdi = str): 1 if it contains '='. Clobbers rax/rcx.
has_eq:
    xor     rcx, rcx
1:
    movzx   eax, byte ptr [rdi + rcx]
    test    al, al
    jz      2f
    cmp     al, '='
    je      3f
    inc     rcx
    jmp     1b
2:
    xor     eax, eax
    ret
3:
    mov     eax, 1
    ret

// has_slash(rdi = str): 1 if it contains '/'. Clobbers rax/rcx.
has_slash:
    xor     rcx, rcx
1:
    movzx   eax, byte ptr [rdi + rcx]
    test    al, al
    jz      2f
    cmp     al, '/'
    je      3f
    inc     rcx
    jmp     1b
2:
    xor     eax, eax
    ret
3:
    mov     eax, 1
    ret

// is_path(rdi = str): 1 if it begins with "PATH=". Clobbers rax.
is_path:
    cmp     byte ptr [rdi], 'P'
    jne     1f
    cmp     byte ptr [rdi + 1], 'A'
    jne     1f
    cmp     byte ptr [rdi + 2], 'T'
    jne     1f
    cmp     byte ptr [rdi + 3], 'H'
    jne     1f
    cmp     byte ptr [rdi + 4], '='
    jne     1f
    mov     eax, 1
    ret
1:
    xor     eax, eax
    ret

// put_line(rdi = ASCIZ): write the string and a newline to stdout.
put_line:
    mov     r8, rdi
    call    uolt_strlen
    mov     rdx, rax
    mov     rsi, r8
    mov     rdi, STDOUT
    call    uolt_write
    mov     rdi, STDOUT
    lea     rsi, [rip + nl_char]
    mov     rdx, 1
    jmp     uolt_write

// err_puts(rdi = ASCIZ) -> stderr.
err_puts:
    mov     r8, rdi
    call    uolt_strlen
    mov     rdx, rax
    mov     rsi, r8
    mov     rdi, STDERR
    jmp     uolt_write

nl_char:      .byte  0x0a
default_path: .asciz "/usr/bin:/bin"
err_pre:      .asciz "uolt-env: "
err_nf:       .asciz ": No such file or directory\n"
err_usage:    .asciz "uolt-env: usage: env [-i] [-u NAME]... [NAME=VALUE]... [command [arg]...]\n"
