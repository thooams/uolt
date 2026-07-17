// libuolt/unlink.S - internal API: uolt_unlink(...). Thin tail call over sys_unlink (Principle V).
#include "uolt.inc"
.text
.globl uolt_unlink
uolt_unlink:
    jmp     sys_unlink
