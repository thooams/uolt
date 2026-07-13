// sys/linux/sleep.S - Linux x86_64 sleep primitive.
//
// sys_sleep(sec in rdi, nsec in rsi): suspend for the given duration using the
// nanosleep syscall (35), resuming with the returned remaining time if a signal
// interrupts it (-EINTR). Owns the Linux syscall number (Principle V). The
// timespec pair lives on the stack (no heap).

#include "uolt.inc"

.set SYS_NANOSLEEP, 35
.set EINTR,         4

.text
.globl sys_sleep
sys_sleep:
    sub     rsp, 40             // req[0..16), rem[16..32)
    mov     [rsp], rdi          // req.tv_sec
    mov     [rsp + 8], rsi      // req.tv_nsec
1:
    mov     rdi, rsp            // req
    lea     rsi, [rsp + 16]     // rem
    mov     rax, SYS_NANOSLEEP
    syscall
    test    rax, rax
    jns     2f                  // completed
    cmp     rax, -EINTR
    jne     2f                  // other error: stop
    mov     rax, [rsp + 16]     // resume with the remaining time
    mov     [rsp], rax
    mov     rax, [rsp + 24]
    mov     [rsp + 8], rax
    jmp     1b
2:
    add     rsp, 40
    ret
