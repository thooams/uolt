// libuolt/arm64/strlen.S - internal API: uolt_strlen(ptr) -> length.
//
// Counts bytes up to (not including) the terminating NUL. x0 = pointer, returns
// the length in x0. Byte-at-a-time: simple and correct; a wider scan is a
// future, measured optimization (Principle VII), not a premature one. Mirrors
// the x86_64 body.

#include "uolt.inc"

.text
.globl uolt_strlen
uolt_strlen:
    mov     x1, x0                      // remember the start pointer
1:
    ldrb    w2, [x0]                    // load a byte
    cbz     w2, 2f                      // reached the NUL terminator?
    add     x0, x0, #1
    b       1b
2:
    sub     x0, x0, x1                  // length = end - start
    ret
