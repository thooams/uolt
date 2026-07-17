// sys/linux/start.S - Linux x86_64 process entry.
//
// The kernel enters at _start with the stack holding argc then the argv
// pointers: [rsp] = argc, [rsp+8] = argv[0], ... This shim normalizes that into
// the common convention uolt_main(argc in rdi, argv in rsi), then exits with the
// status uolt_main returns. Keeping this per-OS is why tools never touch the raw
// entry layout (Principle V); macOS delivers the same args differently.

#include "uolt.inc"

.text
.globl _start
_start:
    mov     rdi, [rsp]          // argc
    lea     rsi, [rsp + 8]      // argv (array of char*, NULL-terminated)
    call    uolt_main           // -> status in rax
    mov     rdi, rax            // status
    call    uolt_exit           // never returns
