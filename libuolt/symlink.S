// libuolt/symlink.S - internal API: uolt_symlink(...). Thin tail call over sys_symlink (Principle V).
#include "uolt.inc"
.text
.globl uolt_symlink
uolt_symlink:
    jmp     sys_symlink
