// libuolt/strlen.S - internal API: uolt_strlen(ptr) -> length.
//
// Counts bytes up to (not including) the terminating NUL. rdi = pointer,
// returns the length in rax. Byte-at-a-time: simple and correct; a wider scan is
// a future, measured optimization (Principle VII), not a premature one.

#include "uolt.inc"

.text
.globl uolt_strlen
uolt_strlen:
    xor     rax, rax                    // length = 0
1:
    cmp     byte ptr [rdi + rax], 0     // reached the NUL terminator?
    je      2f
    inc     rax
    jmp     1b
2:
    ret
