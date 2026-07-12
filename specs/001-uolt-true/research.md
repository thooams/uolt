# Research: uolt-true

Phase 0 output. Resolves technical unknowns before design. `uolt-true` is trivial in
behavior, so most research fixes project-wide infrastructure decisions that every later tool
inherits.

## D1: Assembler and syntax (REVISED)

- **Decision**: The clang integrated assembler (`as`), one toolchain for all targets. x86_64
  sources use Intel syntax via a leading `.intel_syntax noprefix` directive, giving readable
  `mov rax, SYS_EXIT` while staying on clang. Files use the `.s` extension.
- **Rationale**: clang/`as` is already present on macOS and Linux (no install), assembles both
  Mach-O and ELF, and - unlike NASM - also covers a future arm64 target with the same tool.
  Choosing it now avoids a second assembler when Apple Silicon / arm64 macOS is added later.
  `.intel_syntax noprefix` preserves readability (Principle IX) and named constants via
  `.equ`/`.set` in the shared header.
- **Superseded**: NASM (the original choice). Rejected because NASM is x86-only and would force
  a second assembler for arm64, breaking the single-toolchain goal.
- **Alternatives considered**: NASM (x86-only, see above); GAS AT&T default syntax (less
  readable, Principle IX tension - avoided via `.intel_syntax noprefix`); `llvm-mc` (lower
  level, no advantage over `as`).

## D2: Per-OS syscall abstraction

- **Decision**: `sys/<os>/<call>.asm` files own the raw syscall number and the OS calling
  convention; tool code and `libuolt` call only symbolic entry points (`sys_exit`). OS is
  selected at build time by the `Makefile` (host detection), not with runtime branches.
- **Rationale**: Principle V forbids raw syscall numbers in tool code. Linux and macOS differ
  both in numbers and convention: Linux `exit` = `60`; macOS (BSD) `exit` = `0x2000001`.
  Isolating this keeps `true.asm` identical across OSes.
- **Alternatives considered**: `#ifdef`-style runtime OS branch (adds size and branches,
  violates Principle VII); hardcoding numbers in the tool (violates Principle V).

## D3: Which syscall(s) uolt-true needs

- **Decision**: Only `exit`. No `write`, no `read`, no argv parsing.
- **Rationale**: POSIX `true` ignores arguments and produces no output (FR-002..FR-005). The
  kernel places argc/argv on the stack at entry; the program simply ignores them and exits.
- **Alternatives considered**: `exit_group` on Linux (`231`) - unnecessary for a
  single-threaded process; plain `exit` is smaller and sufficient.

## D4: Entry point and linking (platform-aware)

- **Decision**: No libc, no `crt0`, no calls into any library - direct syscalls only. Linking
  differs per OS, per the platform-aware Principle III:
  - **Linux**: entry `_start`, link fully static with `ld` (no `-lc`, no interpreter). Zero
    dynamic dependencies.
  - **macOS**: entry `_main`, link with `ld -e _main -lSystem` (SDK lib path from
    `xcrun --show-sdk-path`). macOS forbids fully static executables and refuses to link
    without `libSystem.dylib` ("dynamic executables must link with libSystem.dylib"), so the
    binary carries `libSystem` as the loader stub only. The code calls **zero** libSystem
    functions; it issues the `exit` syscall directly.
- **Rationale**: Verified empirically on x86_64 macOS: `ld` without `-lSystem` fails; with
  `-lSystem` the binary links, runs, and `exit(0)` via a direct `syscall` works, depending
  only on `/usr/lib/libSystem.B.dylib` (loader, unused at runtime by our code). Linux keeps
  the strict fully-static guarantee.
- **Alternatives considered**: libc `_start`+`main` (drags in the C runtime, breaks III);
  attempting `ld -static` on macOS (unsupported, fails); avoiding `libSystem` on macOS
  (impossible - `ld` rejects it).

## D5: Exit status register mapping

- **Decision**: Status `0` in the syscall's first argument register (`rdi` on Linux; macOS
  BSD convention passes it likewise for the syscall path). `EXIT_SUCCESS = 0` named constant
  in `include/uolt.inc`.
- **Rationale**: Guarantees FR-001 (always exit 0) and Principle IX (named constant, not a
  bare `0`).
- **Alternatives considered**: none meaningful.

## D6: Test strategy for an assembly CLI

- **Decision**: All tests are black-box POSIX-shell scripts driving the built binary, plus a
  syscall trace and a fuzz driver. Layers: unit (exit code + no output), POSIX (args ignored,
  redirected/closed streams), differential (compare exit+output to a reference `true`), fuzz
  (random argv and stream states never yield non-zero or output), trace (`strace`/`dtruss`
  shows only the `exit` syscall and no heap syscalls).
- **Rationale**: Assembly has no compiler safety net (Principle XI). Black-box tests are
  language-agnostic and exercise the real binary. The trace test is what actually proves
  Principles II and IV for this tool.
- **Alternatives considered**: an assembly unit-test framework (none standard, adds
  dependency); linking a C test harness (pulls libc, conflicts with III for the harness's
  view of the binary - kept external instead).

## D7: Benchmark references

- **Decision**: Compare against GNU coreutils `true`, BSD `true` (on macOS), BusyBox, and
  Toybox on time, memory, and size, recorded by `bench/true.sh`.
- **Rationale**: Principle XI requires it; `true` sets the baseline harness for all tools.
- **Alternatives considered**: none; the reference set is fixed by the constitution.

## Open risk (non-blocking)

- **R1: x86_64 macOS availability**. Modern Macs are arm64; running/building x86_64 Mach-O
  needs an Intel Mac or Rosetta-backed toolchain. The constitution scopes x86_64 first with
  ARM deferred. Action: keep the macOS path in `sys/macos/` but treat Linux x86_64 as the
  primary CI target; do not let this block `uolt-true`. Revisit when ARM porting starts.
