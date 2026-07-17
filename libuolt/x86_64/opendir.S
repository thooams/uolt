// libuolt/opendir.S - internal API: uolt_opendir(path) -> fd.
// Open a path as a directory (O_RDONLY|O_DIRECTORY; flag value differs by OS).
// Returns fd (>= 0), -ENOTDIR if the path is not a directory, or another -errno.
#include "uolt.inc"
.text
.globl uolt_opendir
uolt_opendir:
    jmp     sys_opendir
