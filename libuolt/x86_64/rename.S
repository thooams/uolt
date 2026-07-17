// libuolt/rename.S - internal API: uolt_rename(oldpath, newpath). Tail call (Principle V).
#include "uolt.inc"
.text
.globl uolt_rename
uolt_rename:
    jmp     sys_rename
