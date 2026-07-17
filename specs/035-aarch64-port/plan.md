# Implementation Plan: Linux aarch64 (ARM64) Port

**Branch**: `035-aarch64-port` | **Date**: 2026-07-16 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/035-aarch64-port/spec.md`

## Summary

Add an architecture dimension (aarch64) alongside the existing OS dimension so every UOLT tool
builds and runs as a fully-static, direct-syscall, no-heap ELF on Linux aarch64 with byte-for-byte
differential parity vs the system tools, without regressing Linux x86_64. The existing OS
abstraction (`sys/<os>/` owns syscall numbers, `libuolt/` owns shared helpers, tool bodies call
symbolic entry points) is extended with a per-architecture split. Instruction-level code (libuolt
primitives, tool bodies, the entry shim) is re-authored in aarch64 assembly; the aarch64 Linux
syscall set differs from x86_64 (legacy calls dropped in favor of the `*at` family) and that
difference is absorbed in the syscall layer so the shared internal API signatures stay identical.
Delivered incrementally: a thin vertical slice (`true`, `false`, `echo`) proves the whole chain
(entry shim, syscall layer, internal API, one tool body, build selection, CI) before the remaining
33 tools + the `column` extra are ported.

## Technical Context

**Language/Version**: x86_64 and aarch64 assembly, Intel syntax on x86_64 (`.intel_syntax noprefix`), AArch64 (ARM64) unified/GAS syntax on aarch64; assembled by the clang integrated assembler.
**Primary Dependencies**: clang (integrated `as` + driver), GNU ld with custom link script, binutils (`strip`); build/test only. No runtime dependency (fully static ELF).
**Storage**: N/A (stateless CLI tools).
**Testing**: existing shell harness - unit (golden), POSIX, differential vs system tool, fuzz, trace (`strace`). Runs unchanged on aarch64; under CI via qemu-user.
**Target Platform**: Linux aarch64 (new) and Linux x86_64 (existing, must not regress). macOS ARM out of scope.
**Project Type**: single project, hand-written assembly CLI toolset (35 core tools + `column` extra) sharing `sys/` + `libuolt/` + one Makefile.
**Performance Goals**: each tool at least as fast as its system reference on its primary platform; no heap, minimal syscalls (Principle VII/XI). aarch64 performance floor measured natively when a native host is available; parity acceptable under qemu (qemu is a correctness gate, not a benchmark).
**Constraints**: fully static, direct syscalls only, no heap, sections stripped; size discipline "under 1 KB, no bloat" interpreted per-architecture (byte counts differ by encoding). No raw syscall number in tool bodies (Principle V).
**Scale/Scope**: 36 tool bodies + 31 libuolt primitives + ~29 syscall wrappers + entry shim + link script + Makefile arch selection + CI path, delivered thin-slice-first.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Constitution v1.6.0. Per-principle assessment for this feature:

- **I. Assembly-Only**: PASS. aarch64 bodies are hand-written assembly; only build/test tooling is non-assembly.
- **II. Direct Syscalls Only**: PASS on Linux aarch64 - the kernel permits direct `svc #0`. (The macOS-ARM tension recorded in the constitution does not apply; macOS is out of scope here.)
- **III. Zero Dependencies (Platform-Aware)**: PASS. aarch64 Linux binaries are fully static, zero dynamic dependencies, same as x86_64 Linux.
- **IV. No Heap**: PASS. Same stack/registers/mmap discipline; growable failure-checked mmap where already used (sort, uniq, tail, column). aarch64 mmap wrapper mirrors x86_64 semantics.
- **V. Thin Syscall Abstraction + Internal API**: PASS and reinforced. The internal API signatures are held constant across architectures; the `*at` shape difference is hidden in `sys/linux/arm64/`. Tool bodies still name no syscall number. NOTE: this feature widens the abstraction from per-OS to per-OS-and-arch; the constitution's Platform & Architecture Scope already anticipates an `arch/` path.
- **VI. Minimal Size (Targeted)**: PASS with clarification. Existing byte targets are x86_64 encodings; aarch64 holds the same discipline (strip, single segment, no dead code). Exact aarch64 byte counts recorded per tool in its README/spec; a differing count is not a regression.
- **VII. Optimization Measured**: PASS. No speculative optimization; aarch64 bodies mirror the proven x86_64 algorithms. Native benchmarking deferred to a native host; qemu numbers are not used to accept/reject on the performance floor.
- **VIII. POSIX, Not GNU**: PASS (unchanged). Same POSIX behavior per tool; the extra (`column`) stays in `extras/`.
- **IX. Readable & Explicit**: PASS. Named constants; aarch64 syscall numbers live only in `sys/linux/arm64/`. Same comment-as-pedagogy density as x86_64 sources.
- **X. Documentation as Pedagogy**: PASS. README gets aarch64 sizes; each ported tool's spec notes aarch64 specifics. Cross-arch differences (the `*at` absorption) documented in the syscall wrappers.
- **XI. Tested & Benchmarked**: PASS. Same five test layers run on aarch64 via qemu in CI; trace layer uses `strace` (available under qemu-user with caveats, see research). Native benchmark when a native runner exists.

**Governance gate**: the constitution's "Platform & Architecture Scope" currently says "x86_64 first and only, initially. ARM ... is deferred; do not target it now." This feature targets Linux aarch64, so it REQUIRES a constitution amendment (FR-015) to move Linux aarch64 from deferred to in-scope and to record the per-OS-and-arch layout. This is tracked as the first task and must land before implementation is considered governed. macOS ARM stays deferred. No other principle is redefined. See Complexity Tracking.

Result: PASS, gated on the constitution amendment landing first.

## Project Structure

### Documentation (this feature)

```text
specs/035-aarch64-port/
├── plan.md              # This file
├── spec.md              # Feature spec
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output (build-graph entities)
├── quickstart.md        # Phase 1 output (build & test aarch64)
├── contracts/
│   └── internal-api.md  # Phase 1 output: cross-arch stable internal API + syscall-wrapper contract
├── checklists/
│   └── requirements.md  # spec quality checklist
└── tasks.md             # /speckit-tasks output (NOT created here)
```

### Source Code (repository root)

Architecture becomes a first-class directory dimension. The syscall wrappers depend on BOTH os and
arch (numbers differ by both) so they nest arch under os. libuolt primitives and tool bodies depend
on arch only (instructions), OS-independent, so they nest arch directly. The x86_64 sources migrate
once into `x86_64/` subdirectories; no logic changes in that migration.

```text
include/
└── uolt.inc                     # + arch dialect guard: .intel_syntax only when x86_64

sys/
└── linux/
    ├── uolt.ld                  # shared link script if base/flags hold on aarch64; else uolt-arm64.ld
    ├── x86_64/                  # migrated: start.S, write.S, exit.S, mmap.S, ... (existing files)
    └── arm64/                   # new: start.S, write.S, exit.S, mmap.S, openat.S, ... (AT_FDCWD absorbed)

libuolt/
├── x86_64/                      # migrated: strlen.S, write.S, exit.S, ... (existing files)
└── arm64/                       # new: aarch64 re-authored primitives, same symbol names/signatures

src/<tool>/
├── x86_64/<tool>.S              # migrated existing body
└── arm64/<tool>.S               # new aarch64 body, same uolt_main contract

extras/column/
├── x86_64/column.S              # migrated
└── arm64/column.S               # new

Makefile                         # ARCH := $(shell uname -m) normalized; -target per arch; SYSDIR/LIBDIR/SRCDIR arch-aware
.github/workflows/ci.yml         # + linux-arm64 matrix entry (qemu cross-build)
docker/linux-toolchain.Dockerfile# + qemu-user-static / binfmt for arm64 execution
```

**Structure Decision**: Sub-directory-per-arch (chosen over per-file suffix). `sys/linux/<arch>/`,
`libuolt/<arch>/`, `src/<tool>/<arch>/`, `extras/<name>/<arch>/`. Rationale: clean separation, easy
per-arch diff, matches the constitution's anticipated `arch/` path, and keeps each arch's file set
enumerable by directory in the Makefile. Anti-drift (FR-014): both arch bodies of a tool implement
the SAME POSIX behavior and call the SAME internal API symbols; the differential test corpus is
shared, so a body that drifts fails its differential test on that arch. The one-time migration of
x86_64 files into `x86_64/` subdirs is pure `git mv` + Makefile path updates, no logic change,
verified by the x86_64 suite staying green (SC-005).

## Complexity Tracking

> Constitution amendment required; not a principle violation but a governance gate.

| Item | Why Needed | Simpler Alternative Rejected Because |
|------|-----------|--------------------------------------|
| Constitution amendment (v1.6.0 → 1.7.0) moving Linux aarch64 in-scope + recording per-OS-and-arch layout | Current "Platform & Architecture Scope" says x86_64-only, ARM deferred; targeting aarch64 without amending would violate governance | Proceeding without amendment leaves the port ungoverned and contradicts a written scope line (FR-015) |
| Per-OS-and-arch syscall layer (arch nested under os) instead of flat `sys/linux/` | aarch64 numbers differ from x86_64 AND from the OS; both dimensions are real | A single arch's numbers cannot serve both; keeping them flat would smuggle an arch number into a shared file (breaks Principle V) |
| Doubling tool-body files (one per arch) | Instruction sets are disjoint; there is no portable single body for hand-written asm | A compiler-portable source would abandon Principle I (assembly-only) |
