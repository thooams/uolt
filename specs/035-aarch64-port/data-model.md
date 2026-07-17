# Phase 1 Data Model: Build-Graph Entities

This feature has no runtime data model (stateless CLI tools). The "entities" are the build-graph
elements the architecture dimension introduces. They are what tasks operate on.

## Architecture variant

- **Represents**: a target instruction set under an OS. Values: `x86_64` (existing), `arm64` (new).
- **Attributes**: dialect (Intel vs AArch64), syscall convention (D1), syscall number set (D2),
  `struct stat` offsets (D3), clang `-target` triple, `-DUOLT_ARCH_*` define.
- **Selected by**: Makefile from normalized `uname -m`, overridable via `ARCH=`.
- **Validation**: unknown arch → hard build error (FR-012).

## Syscall wrapper (per OS-and-arch)

- **Location**: `sys/linux/<arch>/<call>.S`.
- **Represents**: the thin boundary owning one raw syscall number + trap for one op.
- **Invariants**: owns the number (Principle V/IX); presents a fixed symbolic entry (`sys_write`,
  `sys_open`, …) whose signature is identical across arch; absorbs `AT_FDCWD`/flags for the `*at`
  family (D2) and any struct conversion (utimensat, D2).
- **Relationships**: called only by libuolt primitives and the entry shim, never by tool bodies.

## libuolt primitive (per arch)

- **Location**: `libuolt/<arch>/<name>.S`.
- **Represents**: a shared internal-API routine (`uolt_write`, `uolt_strlen`, `uolt_exit`, …).
- **Invariants**: same global symbol name and same register-level signature on both arches (the
  contract in `contracts/internal-api.md`); tool bodies link against the symbol, not the arch.
- **Relationships**: calls syscall wrappers; called by tool bodies.

## Entry shim (per OS-and-arch)

- **Location**: `sys/linux/<arch>/start.S`.
- **Represents**: `_start` → normalize kernel entry → `uolt_main(argc, argv)` → `uolt_exit(status)`.
- **Invariants**: after normalization, `uolt_main` sees the same argc/argv contract on both arches
  (argc in first arg reg, argv ptr in second). On aarch64 Linux the kernel entry stack layout
  (`[sp]`=argc, `sp+8`=argv) matches x86_64, so the shim differs only in instructions/registers.

## Tool body (per arch)

- **Location**: `src/<tool>/<arch>/<tool>.S` (core), `extras/<name>/<arch>/<name>.S` (extra).
- **Represents**: the tool's logic in one arch's assembly, defining `uolt_main`.
- **Invariants**: implements the same POSIX behavior as its sibling arch body; calls only internal-API
  symbols (no raw syscall number); passes the same shared differential corpus.
- **Relationships**: one body per arch per tool; N tools total = 35 core + 1 extra.

## Shared, arch-independent assets (unchanged, referenced not duplicated)

- `include/uolt.inc`: shared `.set` constants + dirent/mode bits (D4); gains only an arch dialect
  guard (D5). `struct stat` offsets move OUT to arch scope (D3).
- `sys/linux/uolt.ld`: shared link script (D6), forked only if aarch64 load fails.
- Test corpus under `tests/`: shared across arches; the harness is arch-agnostic and reruns as-is.
- `Makefile`: single build; `TOOLNAMES`/`EXTRANAMES`/`EXTRA_<name>` lists stay arch-agnostic once
  `SYSDIR`/`LIBDIR`/tool-source paths are arch-parameterized (D7).

## State transition: the one-time x86_64 migration

```
before:  sys/linux/write.S          libuolt/write.S          src/echo/echo.S
  |  git mv (no logic change)
after:   sys/linux/x86_64/write.S   libuolt/x86_64/write.S   src/echo/x86_64/echo.S
```

Validation of the transition: the x86_64 test suite stays green (SC-005) with byte-identical
binaries (same sources, same flags, only paths moved).
