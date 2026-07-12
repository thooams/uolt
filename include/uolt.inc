// uolt.inc - shared assembly header for UOLT.
//
// Included by every .S source. It only sets the assembler dialect and shared,
// OS-independent named constants (Principle IX: no magic numbers). Raw syscall
// numbers do NOT live here - they belong in sys/<os>/ (Principle V).

// Intel syntax, no % register prefixes, for readable `mov rax, SYS_EXIT`.
.intel_syntax noprefix

// Process exit status for success (POSIX / shell convention).
.set EXIT_SUCCESS, 0
