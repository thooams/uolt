// libuolt/opendst.S - internal API: uolt_opendst(path, mode) -> fd.
// Thin wrapper over per-OS sys_opendst: open O_WRONLY|O_CREAT|O_TRUNC (flag
// values differ by OS). Returns fd (>= 0) or -errno.
#include "uolt.inc"
.text
.globl uolt_opendst
uolt_opendst:
    jmp     sys_opendst
