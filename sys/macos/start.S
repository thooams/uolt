// sys/macos/start.S - macOS x86_64 process entry.
//
// Under LC_MAIN, dyld calls the entry point with the C convention already set
// up: argc in rdi, argv in rsi (envp in rdx, apple in rcx). This differs from
// Linux, where the same values sit on the stack - which is exactly why the entry
// shim is per-OS (Principle V). Verified empirically on x86_64 macOS.
//
// This shim just forwards to uolt_main(argc, argv) and exits with its return
// status.

#include "uolt.inc"

.text
.globl _start
_start:
    call    uolt_main           // rdi=argc, rsi=argv already in place -> status in rax
    mov     rdi, rax            // status
    call    uolt_exit           // never returns
