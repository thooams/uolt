// libuolt/sleep.S - internal API: uolt_sleep(sec, nsec).
//
// Thin wrapper over the per-OS sys_sleep (Principle V): Linux uses nanosleep,
// macOS uses select, but the tool just asks to sleep sec seconds + nsec
// nanoseconds. rdi = sec, rsi = nsec.

#include "uolt.inc"

.text
.globl uolt_sleep
uolt_sleep:
    jmp     sys_sleep
