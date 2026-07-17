# Feature Specification: Linux aarch64 (ARM64) Port

**Feature Branch**: `035-aarch64-port`
**Created**: 2026-07-16
**Status**: Draft
**Input**: User description: "Linux aarch64 (ARM64) port of the UOLT toolset. Add an architecture dimension alongside the existing OS dimension so every tool builds and runs as a fully-static, direct-syscall, tiny ELF on Linux aarch64 exactly as it does on Linux x86_64, with byte-for-byte differential parity vs the system tools."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Run the toolset on an ARM64 Linux machine (Priority: P1)

Someone on an aarch64 Linux host (Raspberry Pi, AWS Graviton, ARM CI runner, Apple Silicon Linux VM) clones UOLT, runs the standard build, and gets working tools that behave identically to the x86_64 build and match the system coreutils output byte-for-byte.

**Why this priority**: Without this, the toolset is x86_64-only. ARM64 is now the majority of new Linux server and dev hardware. This is the entire point of the feature; everything else supports it.

**Independent Test**: On an aarch64 Linux host, run the build and exercise the thin slice (`true`, `false`, `echo`). Each produces the correct exit status / stdout, matches the system tool in a differential run, and is a fully-static ELF under the size floor. Delivers a demonstrable ARM64 toolset even before the remaining tools are ported.

**Acceptance Scenarios**:

1. **Given** an aarch64 Linux host with the toolchain installed, **When** the maintainer runs the standard build with no extra flags, **Then** every ported tool is produced as an `aarch64` static ELF in the build directory without manual per-arch steps.
2. **Given** a freshly built `echo` on aarch64, **When** it is run with the same arguments as the system `echo`, **Then** its stdout is byte-for-byte identical.
3. **Given** any ported tool built on aarch64, **When** its file type and dynamic dependencies are inspected, **Then** it reports as a statically linked ARM aarch64 executable with no shared-library dependencies.
4. **Given** the same source tree, **When** the build runs on an x86_64 host instead, **Then** it still produces correct x86_64 binaries unchanged (no regression to the existing architecture).

---

### User Story 2 - Whole-suite parity on ARM64 (Priority: P2)

All 35 core tools plus the `column` extra run on aarch64 Linux with the same POSIX behavior and the same differential parity guarantees the project already enforces on x86_64.

**Why this priority**: The thin slice proves the toolchain; the value to end users is the full suite. Lower than P1 only because it depends on the P1 chain being validated first.

**Independent Test**: On aarch64 Linux, the full test suite (unit, POSIX, differential, fuzz, trace) passes for every tool at the same coverage as x86_64.

**Acceptance Scenarios**:

1. **Given** the full ported suite on aarch64, **When** the project test target runs, **Then** all layers pass with the same tool coverage as the x86_64 run.
2. **Given** a tool that performs arithmetic, directory reads, or memory mapping on aarch64, **When** compared against the system tool over the shared differential corpus, **Then** output agrees byte-for-byte within the project's documented agreement zone.

---

### User Story 3 - ARM64 is guarded by CI (Priority: P3)

The project's continuous integration exercises the aarch64 build and test path so ARM64 does not silently regress as new tools or changes land.

**Why this priority**: Protects the port over time. Deferrable after the port itself works, but required before the port can be trusted as maintained rather than a one-off.

**Independent Test**: A CI run on a branch that breaks aarch64 (but not x86_64) fails the aarch64 job.

**Acceptance Scenarios**:

1. **Given** a change that builds on x86_64 but breaks on aarch64, **When** CI runs, **Then** the aarch64 job fails and blocks the merge.
2. **Given** the aarch64 CI job, **When** it runs, **Then** it builds and runs the same test layers used for x86_64.

---

### Edge Cases

- ARM64 Linux dropped several legacy syscalls the x86_64 code relies on (no bare `open`, `unlink`, `rename`, `rmdir`, `mkdir`, `link`, `symlink`, `stat`, `lstat`, `utimes`, `access`; only `getdents64`). The behavior seen by callers of the shared internal API MUST stay identical even though the underlying call shape changes (extra current-directory reference argument).
- Building on an x86_64 host while targeting aarch64 (cross-build) versus building natively on aarch64 MUST both yield correct ARM64 binaries.
- A host architecture the port does not support MUST fail the build with a clear message rather than silently producing a wrong-architecture or broken binary.
- Tools with documented capacity bounds (sort input cap, tail/pipe cap, etc.) MUST keep the same documented bounds on aarch64.
- The size floor is architecture-sensitive: instruction encoding differs, so the exact byte counts will differ from x86_64 while the "under 1 KB, no bloat" guarantee still holds.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The toolset MUST build and run on Linux aarch64 (ARM64) with the same tool behavior it has on Linux x86_64.
- **FR-002**: The standard build command MUST select the correct architecture automatically from the host (or an explicit target override) with no per-tool manual steps.
- **FR-003**: Existing Linux x86_64 builds MUST continue to work unchanged; adding ARM64 MUST NOT regress the current architecture.
- **FR-004**: Every ported tool MUST remain a fully-static, direct-syscall, no-heap binary on aarch64, honoring every constitution principle that holds on x86_64 (assembly-only, direct syscalls, no heap, fully static, POSIX-not-GNU).
- **FR-005**: Each ported tool's output MUST match the corresponding system tool byte-for-byte across the project's existing differential agreement zone on aarch64.
- **FR-006**: The shared internal API surface (the helpers tools call) MUST keep identical signatures across architectures, so tool bodies differ only in instruction encoding and not in which helpers they call. Architecture-specific system-call shape differences (including ARM64's current-directory-relative call family) MUST be absorbed below that API.
- **FR-007**: Raw architecture-specific system-call numbers and instruction-level primitives MUST live only in the per-architecture layers; tool bodies MUST NOT name a syscall number or depend on a specific architecture's call set (preserving the existing separation-of-concerns principle across the new architecture dimension).
- **FR-008**: The delivery MUST start with a thin vertical slice of `true`, `false`, and `echo` that exercises the entire chain (entry shim, syscall layer, internal API, one tool body, build selection, and CI) before the remaining tools are ported.
- **FR-009**: The full suite of 35 core tools plus the `column` extra MUST be ported to aarch64.
- **FR-010**: The existing test harness (unit, POSIX, differential, fuzz, trace) MUST run on aarch64 with the same tool coverage, without forking the test scripts per architecture.
- **FR-011**: CI MUST include an aarch64 build-and-test path (native runner or emulated cross-build) that fails when aarch64 regresses independently of x86_64.
- **FR-012**: On an unsupported host architecture, the build MUST fail with a clear, actionable message rather than emit a wrong or broken binary.
- **FR-013**: Each ported binary MUST stay within the project's size discipline (small, no bloat, sections stripped), accepting that the exact byte counts differ from x86_64 due to instruction encoding.
- **FR-014**: The layout that separates architectures in the source tree MUST be chosen to minimize duplication drift between the x86_64 and aarch64 variants, consistent with the project's monorepo/anti-drift stance.
- **FR-015**: The constitution MUST be updated to recognize the architecture dimension (build selection and per-architecture layering) so the port is governed rather than ad hoc.

### Key Entities

- **Architecture variant**: A target instruction set (currently x86_64, adding aarch64) under a given OS. Owns the instruction-level primitives, the syscall numbers/shape, and the entry shim for that target. Selected at build time.
- **Per-tool body**: The tool's logic expressed in one architecture's assembly. One body per architecture per tool; all bodies for a tool implement the same POSIX behavior and call the same shared internal API.
- **Shared internal API**: The stable, architecture-independent set of helper operations tool bodies invoke. Its signatures are fixed across architectures; the per-architecture layer fulfills them.
- **Differential corpus**: The existing shared test inputs and agreement zone used to compare each tool against the system tool; reused unchanged across architectures.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: On an aarch64 Linux host, the standard build completes and produces every ported tool with zero manual per-architecture steps.
- **SC-002**: 100% of ported tools pass the full existing test suite on aarch64 at the same coverage as x86_64.
- **SC-003**: 100% of ported tools produce byte-for-byte identical output to the system tool across the differential agreement zone on aarch64.
- **SC-004**: Every ported aarch64 binary is fully static (zero shared-library dependencies) and stays within the project's size discipline.
- **SC-005**: The x86_64 build and test results are unchanged after the port lands (no regression).
- **SC-006**: The thin slice (`true`, `false`, `echo`) is demonstrably green on aarch64 in CI before any remaining tool is ported.
- **SC-007**: A change that breaks aarch64 but not x86_64 is caught by CI and blocks merge.

## Assumptions

- Target OS for this port is Linux only. macOS on ARM (Apple Silicon) is explicitly out of scope: its kernel does not permit the direct-syscall model this project depends on, so it would require abandoning a core principle and is deferred to a separate decision.
- A usable aarch64 execution environment exists for testing, either a native ARM64 Linux runner or an emulated one; the differential tests require the corresponding system tools to be present there.
- ARM64 Linux uses the current-directory-relative syscall family in place of the dropped legacy calls; absorbing that in the syscall layer keeps the internal API stable (informed guess based on the ARM64 Linux kernel ABI).
- The conventional static load base and single executable segment used by the existing link script remain valid on aarch64; if not, the link configuration is adjusted within this feature.
- The existing size floor target ("under 1 KB, no bloat") is interpreted per-architecture; the guarantee is the discipline, not identical byte counts.
- The full port is large; it is delivered incrementally (thin slice first, then the rest) rather than in one drop, matching the project's per-tool workflow.
