// sys/macos/sleep.S - macOS x86_64 sleep primitive.
//
// macOS has no direct `nanosleep` syscall (libc implements it via
// __semwait_signal), so sys_sleep uses select(2) with a timeout and no
// descriptors, the classic portable sleep. Owns the macOS syscall number
// (Principle V): BSD class 0x2000000 | 93. The timeval is on the stack (no heap).
//
// sys_sleep(sec in rdi, nsec in rsi): microsecond resolution (nsec is truncated
// to microseconds). On EINTR it simply retries the full interval - a slight
// over-sleep on the non-authoritative platform, which the constitution accepts.

#include "uolt.inc"

.set SYS_SELECT, 0x200005D
.set EINTR,      4

.text
.globl sys_sleep
sys_sleep:
    sub     rsp, 16             // struct timeval { tv_sec; tv_usec; }
    mov     [rsp], rdi          // tv_sec
    mov     rax, rsi            // tv_usec = nsec / 1000
    xor     rdx, rdx
    mov     rcx, 1000
    div     rcx
    mov     [rsp + 8], rax
1:
    xor     rdi, rdi            // nfds = 0
    xor     rsi, rsi            // readfds = NULL
    xor     rdx, rdx            // writefds = NULL
    xor     r10, r10            // errorfds = NULL (4th arg -> r10 for syscall)
    mov     r8, rsp             // timeout
    mov     rax, SYS_SELECT
    syscall
    jnc     2f                  // completed
    cmp     rax, EINTR
    jne     2f                  // other error: stop
    jmp     1b                  // interrupted: retry
2:
    add     rsp, 16
    ret
