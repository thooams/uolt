// uolt.inc - shared assembly header for UOLT.
//
// Included by every .S source. It only sets the assembler dialect and shared,
// OS-independent named constants (Principle IX: no magic numbers). Raw syscall
// numbers do NOT live here - they belong in sys/<os>/ (Principle V).

// Intel syntax, no % register prefixes, for readable `mov rax, SYS_EXIT`.
.intel_syntax noprefix

// Process exit status codes (POSIX / shell convention).
.set EXIT_SUCCESS, 0
.set EXIT_FAILURE, 1

// Directory-entry field offsets for the directory-reading tools (ls, later rm -r).
// The record length sits at offset 16 in both the Linux linux_dirent64 and the
// macOS 64-bit dirent; the inline name starts at a different offset per OS. The
// build passes -DUOLT_OS_LINUX or -DUOLT_OS_MACOS (see the Makefile).
.set DIRENT_RECLEN_OFF, 16
#ifdef UOLT_OS_MACOS
.set DIRENT_NAME_OFF, 21
#else
.set DIRENT_NAME_OFF, 19
#endif
