# Phase 0 Research: Linux aarch64 Port

All items below resolve the unknowns implied by the Technical Context. No open NEEDS
CLARIFICATION remains after this phase.

## D1. aarch64 Linux syscall ABI

- **Decision**: Syscall number in `x8`, arguments in `x0`-`x5`, trap via `svc #0`, return value
  (or negative errno in `-4095..-1`) in `x0`. This replaces the x86_64 `rax`/`rdi,rsi,rdx,r10,r8,r9`/`syscall` convention.
- **Rationale**: Standard AArch64 Linux kernel ABI; direct syscalls are permitted (unlike macOS ARM).
- **Alternatives considered**: Calling libc wrappers — rejected, violates Principles II/III.
- **Impact**: Every `sys/linux/arm64/*.S` wrapper and the entry shim uses this convention. Register
  role differs from x86_64's `r10` (4th arg) quirk; aarch64 has no such quirk.

## D2. Legacy syscalls dropped on aarch64 → `*at` family (the ABI-shape risk)

- **Decision**: aarch64 Linux (asm-generic unistd) does NOT provide `open`, `mkdir`, `rmdir`,
  `unlink`, `rename`, `link`, `symlink`, `stat`, `lstat`, `access`, `utimes`, or `getdents`. Use
  the directory-fd-relative replacements and absorb `AT_FDCWD` (= -100) inside the wrapper so the
  libuolt-facing signature is unchanged.
- **Rationale**: Keeps the internal API stable across arch (Principle V, FR-006); tool bodies and
  libuolt callers pass the same args they pass on x86_64; the wrapper prepends the dirfd.
- **Mapping** (aarch64 generic numbers):

  | libuolt op | x86_64 call (num) | aarch64 call (num) | wrapper absorbs |
  |-----------|-------------------|--------------------|-----------------|
  | read | read (0) | read (63) | - |
  | write | write (1) | write (64) | - |
  | open | open (2) | openat (56) | dirfd=AT_FDCWD |
  | close | close (3) | close (57) | - |
  | lseek | lseek (8) | lseek (62) | - |
  | mmap | mmap (9) | mmap (222) | same flags/args |
  | munmap | munmap (11) | munmap (215) | - |
  | exit | exit_group (231)/exit (60) | exit_group (94)/exit (93) | - |
  | getcwd | getcwd (79) | getcwd (17) | - |
  | execve | execve (59) | execve (221) | - |
  | getdents | getdents64 (217) | getdents64 (61) | - |
  | mkdir | mkdir (83) | mkdirat (34) | dirfd=AT_FDCWD |
  | rmdir | rmdir (84) | unlinkat (35) | dirfd=AT_FDCWD, flags=AT_REMOVEDIR (0x200) |
  | unlink | unlink (87) | unlinkat (35) | dirfd=AT_FDCWD, flags=0 |
  | rename | rename (82) | renameat (38) | olddirfd=newdirfd=AT_FDCWD |
  | link | link (86) | linkat (37) | dirfd=AT_FDCWD ×2, flags=0 |
  | symlink | symlink (88) | symlinkat (36) | newdirfd=AT_FDCWD |
  | chmod | chmod (90) | fchmodat (53) | dirfd=AT_FDCWD, flags=0 |
  | access | access (21) | faccessat (48) | dirfd=AT_FDCWD, flags=0 |
  | stat | stat (4) | newfstatat (79) | dirfd=AT_FDCWD, flags=0 |
  | lstat | lstat (6) | newfstatat (79) | dirfd=AT_FDCWD, flags=AT_SYMLINK_NOFOLLOW (0x100) |
  | utimes | utimes (235) | utimensat (88) | dirfd=AT_FDCWD; convert timeval→timespec |
  | nanosleep | nanosleep (35) | nanosleep (101) | - |

- **Alternatives considered**: `renameat2`/`statx`/`faccessat2` — rejected for v1; the classic `*at`
  calls match existing behavior exactly and avoid newer-kernel dependencies.
- **Watch items**: `utimensat` takes `struct timespec[2]` not `struct timeval[2]`; `touch`'s wrapper
  must convert. `rmdir`→`unlinkat|AT_REMOVEDIR` shares the number with `unlink`; distinguished only
  by flags.

## D3. `struct stat` field offsets differ between x86_64 and aarch64

- **Decision**: The stat field offsets are architecture-specific and MUST live in the arch layer,
  not in the shared `include/uolt.inc`. aarch64 uses the asm-generic `struct stat`.

  | field | x86_64 offset | aarch64 offset |
  |-------|---------------|----------------|
  | st_mode | 24 | 16 |
  | st_size | 48 | 48 |

- **Rationale**: `statmode`/`lstatmode`/`statsize` read these offsets; a wrong offset silently
  returns garbage. x86_64 `struct stat` orders `st_nlink` before `st_mode`; aarch64 orders `st_mode`
  earlier. `st_size` coincidentally matches at 48 but MUST NOT be assumed portable by luck — pin it
  per arch.
- **Alternatives considered**: One shared offset set — rejected, incorrect on aarch64.
- **Impact**: Add arch-guarded `.set ST_MODE_OFF` / `.set ST_SIZE_OFF` (in the arch libuolt sources
  or an arch-guarded block in `uolt.inc`). `test`, `ln`, `mv`, `cp`, `chmod`, `ls` depend on this.

## D4. `linux_dirent64` and `st_mode` bit constants are arch-independent

- **Decision**: `DIRENT_RECLEN_OFF`/`DIRENT_NAME_OFF`/`DIRENT_TYPE_OFF`, the `DT_*` values, the
  `S_IF*`/`S_IS*` mode bits, and `R_OK/W_OK/X_OK` in `uolt.inc` are identical on aarch64 Linux; keep
  them shared. `getdents64` returns the same `linux_dirent64` layout on both arches.
- **Rationale**: These are kernel-ABI-stable across Linux arches; only the syscall numbers and the
  `struct stat` layout (D3) differ. Confirms the existing `#ifdef UOLT_OS_MACOS` dirent guard needs
  no arch variant.

## D5. Assembler dialect guard

- **Decision**: `.intel_syntax noprefix` is emitted only for x86_64. aarch64 sources use native
  AArch64 (GAS/unified) syntax. Guard in `include/uolt.inc` on an arch macro (`-DUOLT_ARCH_X86_64`
  vs `-DUOLT_ARCH_ARM64`) passed by the Makefile.
- **Rationale**: `.intel_syntax` is an x86-only directive; including it in an aarch64 assembly unit
  is meaningless/harmful. The shared `.set` constants remain valid for both (assembler-level, ISA-agnostic).
- **Alternatives considered**: Separate `uolt-x86.inc`/`uolt-arm.inc` headers — rejected, duplicates
  the shared constant block and invites drift; one guarded header is DRY.

## D6. Link script / static layout on aarch64

- **Decision**: Start by reusing `sys/linux/uolt.ld` unchanged (single R+X `PT_LOAD`, base
  `0x400000`, headers folded, `.bss`/notes discarded). Validate the produced aarch64 ELF loads and
  runs; if the base or segment flags misbehave, fork `sys/linux/uolt-arm64.ld` selected by the
  Makefile. `.bss` discard rule stands, so aarch64 buffers stay on stack or mmap (same as x86_64).
- **Rationale**: The link script is largely arch-independent (ELF program-header geometry, not
  instructions). `0x400000` is a conventional static base on aarch64 Linux too. Keep it shared unless
  measurement says otherwise (Principle VII).
- **Alternatives considered**: Immediately forking a per-arch script — rejected as premature; only
  fork if a concrete load failure demands it.
- **Outcome (T009, verified)**: the shared `sys/linux/uolt.ld` works UNCHANGED on aarch64. A
  `true`/`false` unit cross-linked with it (`clang -target aarch64-linux-gnu -fuse-ld=lld
  -Wl,-T,sys/linux/uolt.ld`) produces an ELF64 AArch64 `EXEC` with a single `LOAD` segment at
  `0x400000`, no dynamic section (fully static), 368 bytes stripped, and runs correctly under
  `qemu-aarch64-static` (true → 0, false → 1). No `uolt-arm64.ld` fork was needed.

## D7. Build selection in the Makefile

- **Decision**: Detect `ARCH := $(shell uname -m)` and normalize (`aarch64|arm64 → arm64`,
  `x86_64|amd64 → x86_64`); unknown → hard error (FR-012). Select `SYSDIR := sys/linux/$(ARCH)`,
  `LIBDIR := libuolt/$(ARCH)`, and tool source `src/<t>/$(ARCH)/<t>.S`. Pass `-target
  aarch64-linux-gnu` (arm64) or `-target x86_64-linux-gnu` and the matching `-DUOLT_ARCH_*`.
  Cross-build honored via an overridable `ARCH=` on the command line for the qemu container.
- **Rationale**: One host-detected default, zero manual per-tool steps (FR-002); explicit override
  enables the qemu cross-build in CI. The existing `EXTRA_<name>` lists reference files by basename,
  so they stay arch-agnostic once `SYSDIR`/`LIBDIR` are arch-aware.
- **Alternatives considered**: A separate `Makefile.arm64` — rejected, forks the whole build graph
  and drifts.

## D8. CI: qemu-user cross-build (chosen)

- **Decision**: Add a `linux-arm64` CI matrix entry that runs on the free x86_64 GitHub runner,
  builds with `-target aarch64-linux-gnu`, and executes the produced binaries under
  `qemu-aarch64-static` via `binfmt_misc` (registered by `qemu-user-static`). The
  `docker/linux-toolchain.Dockerfile` gains `qemu-user-static` (and `binfmt-support`) so the same
  container runs the tests. Native ARM runner deferred (quota/billing).
- **Rationale**: Zero ARM runner cost, reproducible, mirrors the existing Linux container flow.
- **Trace-layer caveat**: `strace` under `qemu-user` traces the emulated guest imperfectly; the
  Principle XI syscall-trace assertion (no `brk`, only expected syscalls) is best run on a native
  aarch64 host. Under qemu, the trace test either runs against qemu's own strace support or is marked
  environment-skipped with a recorded reason (same pattern as the macOS dtruss-under-SIP skip). The
  no-heap guarantee is additionally enforced structurally (`.bss` discarded, no `malloc`, mmap-only).
- **Alternatives considered**: Native `ubuntu-24.04-arm` runner — kept as a future upgrade for real
  benchmarks; not required for the correctness gate.

## D9. Delivery order (thin slice first)

- **Decision**: Phase A migrates x86_64 files into `x86_64/` subdirs + makes the Makefile arch-aware
  (x86_64 stays green, SC-005). Phase B ports the thin slice `true`/`false`/`echo` to aarch64 + adds
  the qemu CI job (SC-006). Phase C ports the remaining tools in the constitution's build order,
  simplest first, each with full test parity. `column` last (extra).
- **Rationale**: De-risks the toolchain/CI before the bulk of body re-authoring (FR-008); every
  subsequent tool reuses a proven chain.
- **Alternatives considered**: Big-bang port — rejected, no early validation and a huge unreviewable diff.

## D10. Constitution amendment (governance)

- **Decision**: Amend "Platform & Architecture Scope" to move **Linux aarch64** from deferred to
  in-scope, record the per-OS-and-arch layout (`sys/linux/<arch>/`, `libuolt/<arch>/`,
  `src/<t>/<arch>/`), and keep **macOS ARM** explicitly deferred (direct-syscall tension unresolved).
  MINOR bump v1.6.0 → 1.7.0. Land before implementation (FR-015).
- **Rationale**: The current text forbids targeting ARM now; governance requires the scope line to
  match the work. macOS ARM stays out for the recorded direct-syscall reason.
- **Alternatives considered**: Skipping the amendment — rejected, leaves the port contradicting a
  written rule.
