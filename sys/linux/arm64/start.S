// sys/linux/arm64/start.S - Linux aarch64 process entry.
//
// The kernel enters at _start with the stack holding argc then the argv
// pointers: [sp] = argc, [sp+8] = argv[0], ... (sp is 16-byte aligned per the
// AArch64 ABI). This shim normalizes that into the common convention
// uolt_main(argc in x0, argv in x1), then exits with the status uolt_main
// returns. Keeping this per-OS-and-arch is why tools never touch the raw entry
// layout (Principle V); x86_64 delivers the same args in rdi/rsi.

#include "uolt.inc"

.text
.globl _start
_start:
    ldr     x0, [sp]            // argc
    add     x1, sp, #8          // argv (array of char*, NULL-terminated)
    bl      uolt_main           // -> status in x0
    bl      uolt_exit           // status already in x0; never returns
