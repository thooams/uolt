// libuolt/chmod.S - internal API: uolt_chmod(path, mode). Tail call (Principle V).
#include "uolt.inc"
.text
.globl uolt_chmod
uolt_chmod:
    jmp     sys_chmod
