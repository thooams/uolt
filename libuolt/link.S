// libuolt/link.S - internal API: uolt_link(...). Thin tail call over sys_link (Principle V).
#include "uolt.inc"
.text
.globl uolt_link
uolt_link:
    jmp     sys_link
