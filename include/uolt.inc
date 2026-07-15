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
.set DIRENT_TYPE_OFF, 20
#else
.set DIRENT_NAME_OFF, 19
.set DIRENT_TYPE_OFF, 18
#endif

// d_type values (DT_*) reported by getdents (may be DT_UNKNOWN on some
// filesystems, in which case a caller falls back to opening the path).
.set DT_UNKNOWN, 0
.set DT_DIR,     4
.set DT_REG,     8
.set DT_LNK,     10

// File-mode bits from st_mode (POSIX; identical on Linux and macOS), used by the
// stat-based file tests in `test`. S_IF* are the type field (mask S_IFMT); the
// S_IS* are the set-user-ID / set-group-ID / sticky permission bits.
.set S_IFMT,   0xF000
.set S_IFREG,  0x8000
.set S_IFDIR,  0x4000
.set S_IFLNK,  0xA000
.set S_IFIFO,  0x1000
.set S_IFSOCK, 0xC000
.set S_IFBLK,  0x6000
.set S_IFCHR,  0x2000
.set S_ISUID,  0x0800
.set S_ISGID,  0x0400
.set S_ISVTX,  0x0200

// access(2) permission-check bits.
.set R_OK, 4
.set W_OK, 2
.set X_OK, 1
