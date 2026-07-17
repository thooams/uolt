// libuolt/openapp.S - internal API: uolt_openapp(path, mode) -> fd.
// Open O_WRONLY|O_CREAT|O_APPEND (flag values differ by OS). Returns fd or -errno.
#include "uolt.inc"
.text
.globl uolt_openapp
uolt_openapp:
    jmp     sys_openapp
