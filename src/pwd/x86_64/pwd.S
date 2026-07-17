// src/pwd/pwd.S - uolt-pwd: the POSIX `pwd` utility.
//
// Prints the absolute pathname of the current working directory, followed by a
// newline, and exits 0. This is the physical path (like `pwd -P`): it comes from
// the kernel's view of the directory, not the $PWD environment variable. Options
// (-L / -P) are ignored in v1; arguments are ignored.
//
// Called as uolt_main(argc, argv). The cwd is fetched into a stack buffer (no
// heap, Principle IV) via uolt_getcwd, whose per-OS implementation hides the fact
// that Linux uses the getcwd syscall while macOS must go through
// open(".")+fcntl(F_GETPATH) (macOS blocks direct __getcwd).

#include "uolt.inc"

.set STDOUT, 1
.set BUFSZ,  4096               // >= PATH_MAX / MAXPATHLEN

.text
.globl uolt_main
uolt_main:
    push    rbp
    mov     rbp, rsp
    sub     rsp, BUFSZ          // stack buffer for the path

    mov     rdi, rsp            // buf
    mov     rsi, BUFSZ          // size
    call    uolt_getcwd
    test    rax, rax
    js      .error              // negative -> failure

    mov     rdi, rsp            // strlen(buf)
    call    uolt_strlen
    mov     rdx, rax            // length
    mov     rsi, rsp            // buf
    mov     rdi, STDOUT
    call    uolt_write

    mov     rdi, STDOUT         // trailing newline
    lea     rsi, [rip + nl_char]
    mov     rdx, 1
    call    uolt_write

    xor     eax, eax            // exit status 0
    jmp     .done
.error:
    mov     eax, 1              // exit status 1 on getcwd failure
.done:
    mov     rsp, rbp
    pop     rbp
    ret

nl_char: .byte 0x0a
