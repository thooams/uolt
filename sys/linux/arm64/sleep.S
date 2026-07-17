// sys/linux/arm64/sleep.S - Linux aarch64 sleep primitive, via nanosleep.
// sys_sleep(sec=x0, nsec=x1): suspend, resuming with the remaining time if a
// signal interrupts (-EINTR). timespec pair on the stack (no heap).
#include "uolt.inc"
.set SYS_NANOSLEEP, 101
.set EINTR,         4
.text
.globl sys_sleep
sys_sleep:
    sub     sp, sp, #32                 // req[0..16), rem[16..32)
    str     x0, [sp]                    // req.tv_sec
    str     x1, [sp, #8]                // req.tv_nsec
1:
    mov     x0, sp                      // &req
    add     x1, sp, #16                 // &rem
    mov     x8, SYS_NANOSLEEP
    svc     #0
    cmp     x0, #0
    b.ge    2f                          // completed
    cmn     x0, #EINTR                  // x0 == -EINTR ?
    b.ne    2f                          // other error: stop
    ldr     x2, [sp, #16]               // resume with remaining time
    str     x2, [sp]
    ldr     x2, [sp, #24]
    str     x2, [sp, #8]
    b       1b
2:
    add     sp, sp, #32
    ret
