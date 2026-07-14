// libuolt/umask.S - internal API: uolt_umask(mask) -> previous mask.
#include "uolt.inc"
.text
.globl uolt_umask
uolt_umask:
    jmp     sys_umask
