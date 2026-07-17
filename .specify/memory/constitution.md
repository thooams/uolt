<!--
Sync Impact Report
==================
Version change: 1.6.0 → 1.7.0
Bump rationale: MINOR. Moves Linux aarch64 (ARM64) from deferred to in-scope in "Platform &
  Architecture Scope" and records the per-OS-and-arch source layout the port introduces
  (`sys/linux/<arch>/`, `libuolt/<arch>/`, `src/<tool>/<arch>/`, `extras/<name>/<arch>/`, with
  `<arch>` in {x86_64, arm64}). No principle is redefined: Principle V's thin syscall
  abstraction is widened from per-OS to per-OS-and-arch (the aarch64 `*at`-family divergence is
  absorbed in `sys/linux/arm64/` so internal-API signatures stay identical across arches);
  Principle VI's size discipline is read per-architecture (byte counts differ by encoding, a
  differing count is not a regression). macOS ARM (Apple Silicon) STAYS deferred: Apple's
  restriction on direct syscalls keeps the Principle II tension unresolved for that target. No
  existing rule is removed.

Version change: 1.5.1 → 1.6.0
Bump rationale: MINOR. Adds a new section, "UOLT Extras (Non-Core Collection)", and a pointer
  to it from Principle VIII. The core library stays a strict POSIX subset (Principle VIII is
  unchanged for it); the amendment sanctions a clearly separated `extras/` collection of
  non-core, non-POSIX convenience tools (first member: `uolt-column`). Extras are exempt ONLY
  from Principle VIII (POSIX-only) and still obey every other principle (assembly-only, direct
  syscalls, zero deps, no heap, thin syscall abstraction, size targets, readability,
  documentation, tested + benchmarked). This is not a second build of a core tool and not a
  runtime mode flag, so it does not reintroduce the dual-build cost Principle VIII forbids: each
  extra is its own single binary reusing the shared `sys/` + `libuolt/` infrastructure. No
  existing rule is redefined or removed.

Version change: 1.5.0 → 1.5.1
Bump rationale: PATCH. Clarifies Principle IV: a whole-input tool (e.g. `sort`) MAY use an
  explicit, failure-checked mmap region - including a growable one (map larger, copy, munmap) -
  instead of a fixed buffer that would silently truncate, since that is a tool-owned reservation
  with a reported out-of-memory path, not a hidden heap. No rule is redefined or removed; this
  makes an already-permitted use explicit.

Version change: 1.4.0 → 1.5.0
Bump rationale: MINOR. Hardens Principle VIII with an explicit scope line: an option MAY be
  implemented iff POSIX specifies it for that tool; no GNU-only options; exactly one
  POSIX-first library and binary per tool (no "extended"/dual build, no runtime extended-mode
  flag). Grandfathers the closed set of BSD+GNU-universal extras already shipped (`seq` and
  its `-s`/`-w`, `grep -w`, `find -maxdepth`). No existing rule is redefined or removed.

Prior amendment history below.

Version change: 1.3.0 → 1.4.0
Bump rationale: MINOR. Adds an explicit performance-vs-reference gate: each tool MUST be at
  least as fast as the standard tool it replaces (ideally faster), measured with hyperfine on
  the primary benchmark platform (Linux x86_64); where process-spawn overhead dominates
  (macOS), parity within measurement noise satisfies the rule. Folded into Principle XI and
  the quality gates. No existing rule is redefined or removed.

Version change: 1.2.0 → 1.3.0
Bump rationale: MINOR. Makes Principle III platform-aware so native macOS binaries are
  possible: Linux stays fully static with zero dynamic dependencies, while macOS (which the
  OS forbids from linking fully static) is allowed the single unavoidable `libSystem.dylib`
  loader dependency provided the code makes zero calls into it and uses only direct syscalls.
  This relaxes an absolute rule for one platform on physical-impossibility grounds; it does
  not weaken the intent (no libc/runtime usage). Also records the toolchain baseline
  (clang/`as`, Intel syntax via `.intel_syntax noprefix`) chosen to keep one assembler across
  x86_64 now and arm64 later.

  Prior amendments:
  - 1.1.0 → 1.2.0: hardened Principle XI (differential, fuzz, partial-I/O, syscall-trace).
  - 1.0.0 → 1.1.0: added the README-per-command rule (Principle X + README gate).

Principles established:
  - I. Assembly-Only Production Code
  - II. Direct Syscalls Only
  - III. Zero Dependencies (Platform-Aware)
  - IV. No Heap, No Hidden Allocation
  - V. Thin Syscall Abstraction + Internal API
  - VI. Minimal Size (Targeted)
  - VII. Optimization: Measured, Never Premature
  - VIII. POSIX, Not GNU
  - IX. Readable & Explicit
  - X. Documentation as Pedagogy
  - XI. Tested & Benchmarked

Added sections:
  - Platform & Architecture Scope
  - Size & Startup Targets
  - Build & Tooling
  - Scope Discipline (Roadmap)

Removed sections: none (Technical Constraints folded into the above)

Templates requiring updates:
  - .specify/templates/plan-template.md         ✅ reviewed, Constitution Check gate compatible
  - .specify/templates/spec-template.md         ✅ reviewed, no mandatory-section conflict
  - .specify/templates/tasks-template.md        ✅ reviewed, task categories compatible
  - .specify/templates/checklist-template.md    ✅ reviewed, no change required

Deferred TODOs: none
-->

# UOLT Constitution

**UOLT - Ultra Optimised Lightweight Toolset.** A handcrafted suite of Unix utilities
written entirely in assembly, designed for minimal size, predictable performance, and zero
unnecessary abstraction. Shared logic lives in `libuolt`; each utility ships as a
`uolt-<name>` executable (e.g. `uolt-ls`, `uolt-cat`, `uolt-pwd`).

## Core Principles

### I. Assembly-Only Production Code
All production code MUST be written in assembly. No C. No Rust. No libc. Only build scripts
and test/benchmark tooling MAY use another language.
**Rationale**: Hand-written assembly is the means by which UOLT reaches its size and
performance goals; it is the defining constraint of the project.

### II. Direct Syscalls Only
Every tool MUST talk to the kernel directly through system calls (`open`, `read`, `write`,
`close`, `stat`, `getdents`, `fork`, `execve`, `mmap`, and peers). No intermediate layer,
wrapper library, or runtime sits between a tool and the kernel.
**Rationale**: Every abstraction layer costs instructions, size, and predictability;
removing them is the whole point.

### III. Zero Dependencies (Platform-Aware)
Each binary MUST be self-contained and make zero calls into any C library, runtime, or
external code: all functionality goes through direct syscalls (Principle II). Dynamic linkage
rules are platform-aware, because macOS physically forbids fully static executables:
- **Linux**: binaries MUST be fully static with no dynamic dependency of any kind; a tool
  runs with nothing but the kernel present.
- **macOS**: the only permitted dependency is the single `libSystem.dylib` that the OS
  requires as the loader for every executable. The tool MUST NOT call any function from it;
  it uses direct syscalls only. No other dylib, no libc usage.
No libc, no libgcc, no runtime is ever *used* on any platform.
**Rationale**: Autonomy guarantees minimal size, predictable startup, and no external surface
that can bloat or break a tool. macOS makes a fully static binary impossible, so the rule
targets what matters - zero library *usage* and direct syscalls - while tolerating the one
loader stub the OS imposes.

### IV. No Heap, No Hidden Allocation
The heap is forbidden. No `malloc`, no runtime that allocates on the tool's behalf, no hidden
heap. Memory MUST come from the stack, registers, or static buffers. `mmap` MAY be used only
when genuinely necessary and MUST be justified in the change. Specifically, a tool that must hold
an unbounded amount of input at once (e.g. `sort`) MAY use an explicit, failure-checked `mmap`
region - including a growable one (map larger, copy, `munmap` the old) - in preference to a fixed
buffer that would silently truncate. This is an explicit, tool-owned reservation with a reported
out-of-memory path, not a hidden heap: the intent (no libc/runtime allocation, no silent failure)
is preserved.
**Rationale**: Heap allocation adds size, unpredictability, and failure modes UOLT refuses to
carry; an explicit mmap that reports failure keeps those properties while letting the few
whole-input tools stay correct at scale.

### V. Thin Syscall Abstraction + Internal API
A tool MUST NOT contain a raw syscall number. Platform differences live behind a thin
per-OS layer (e.g. `sys/linux/write.asm`, `sys/macos/write.asm`); tool code calls symbolic
entry points such as `sys_write` and `sys_read`. Shared routines (`print_string`, `strlen`,
`strcmp`, `memcpy`, `exit`, `parse_args`, ...) MUST live in one internal API in `libuolt` and
be reused by every tool, never duplicated.
**Rationale**: A single syscall boundary and a shared internal API are what make an
assembly codebase maintainable and portable across OSes.

### VI. Minimal Size (Targeted)
Each tool MUST declare and hold a binary-size target (see Size & Startup Targets). Every byte
MUST be justified: no dead code, no unused sections. Exceeding a target requires an explicit,
approved update to that target.
**Rationale**: "Lightweight" is a named pillar; size is a first-class, enforced metric.

### VII. Optimization: Measured, Never Premature
Every optimization MUST be measured: benchmark before, benchmark after. Every design choice
serves fewer instructions, less memory, fewer branches, fewer syscalls, or fewer allocations.
Every instruction MUST have a reason; if an instruction can be removed, it is removed. No
speculative optimization without a measurement backing it.
**Rationale**: Optimization without measurement is guesswork; discipline keeps gains real.

### VIII. POSIX, Not GNU
Tools target POSIX behavior, not GNU. Core utilities (`pwd`, `ls`, `cp`, `mv`, `mkdir`,
`touch`, `cat`, ...) MUST behave as POSIX expects. Supported options and any intentional
deviation MUST be documented per tool.

**Scope line (single POSIX-first library).** A tool option MAY be implemented if and only if
POSIX specifies that option for that tool. GNU-only (or otherwise non-POSIX) options are OUT
of scope and MUST NOT be added. There is exactly ONE library and ONE binary per tool: the
project MUST NOT grow a second "extended"/GNU build, nor a runtime mode flag that toggles
extra behavior — a dual mode would double the test surface and inflate binary size, defeating
Principles IV and VI. The clean side effect of this line: POSIX-specified options are the set
on which BSD and GNU generally agree, so each is differential-testable against the system tool
on both platforms without special-casing; a case that needs a BSD-vs-GNU gate is a signal that
the option is drifting past POSIX.

**Grandfathered extras.** A small number of non-POSIX but BSD+GNU-universal options predate
this line and MAY remain (they are already implemented and tested): `seq` and its `-s`/`-w`
(the whole tool is non-POSIX), `grep -w`, and `find -maxdepth`. This list is closed: no
further non-POSIX options may be added under it.

**Extras exception.** Non-core, non-POSIX convenience tools are permitted ONLY inside the
separate `extras/` collection defined in "UOLT Extras (Non-Core Collection)" below. The core
utilities named in this principle remain a strict POSIX subset with no such tools.

**Rationale**: POSIX is a stable, achievable contract on which the two reference
implementations agree; chasing GNU breadth, or splitting into POSIX/extended builds, would
sink the size and simplicity goals and the byte-for-byte differential guarantee.

### IX. Readable & Explicit
No magic code. Prefer named constants over bare numbers (`mov rax, SYS_WRITE`, never
`mov rax, 1`). The code MUST be readable by a systems developer, an outcome often neglected in
assembly projects and treated here as a requirement.
**Rationale**: Readability is what keeps a hand-written assembly toolset maintainable.

### X. Documentation as Pedagogy
Every optimization MUST be explained: why this instruction, why this register, why this loop.
The project is pedagogical as well as functional; unexplained cleverness is a defect.
Additionally, whenever a command is developed, the README MUST be updated with an entry for
that command carrying at minimum its name and its binary size, plus any other relevant
information (supported POSIX options, benchmark highlights, notable constraints). No command
is considered done until its README entry exists and is accurate.
**Rationale**: Documented reasoning turns a fast toolset into a teachable one and protects
future maintainers; a current README is the project's public record of what ships and how
small it is.

### XI. Tested & Benchmarked
Every tool MUST carry unit tests, POSIX-conformance tests, and regression tests. Because the
code is hand-written assembly with no compiler safety net, tests carry the full weight of
robustness and MUST additionally include:
- **Differential tests**: for the same input, the tool's stdout, stderr, and exit code MUST
  match a reference implementation (GNU, or BSD on macOS) wherever the behavior is specified.
- **Fuzzing**: tools MUST be fuzzed with random and malformed input and MUST never crash,
  segfault, or diverge from the reference on valid input.
- **Partial-I/O edge cases**: tests MUST exercise short/partial `read` and `write` returns,
  empty input, very large input, missing final newline, closed pipes (SIGPIPE), absent files,
  and permission errors, asserting correct errno/exit behavior.
- **Syscall-trace verification**: a trace (`strace` on Linux, `dtruss` on macOS) MUST confirm
  no hidden syscalls, no heap allocation, and only the expected syscalls (proving Principles
  II and IV).

Every tool MUST also have an integrated benchmark comparing it against GNU, BSD (on macOS),
BusyBox, and Toybox across time, memory, and size. All test and benchmark results MUST be
recorded so regressions are detectable.

**Performance floor (at worst equal, at best faster)**: every tool MUST be at least as fast
as the standard tool it replaces, and should be faster. This is measured with `hyperfine` on
the primary benchmark platform, **Linux x86_64**, where the tool's own cost is observable; a
tool measurably slower than its reference there is rejected. On platforms where process-spawn
overhead dominates and swamps the tool's own work (notably macOS, ~3 ms of exec/dyld cost),
**parity within measurement noise** satisfies the rule - we do not require beating fixed OS
overhead we do not control.
**Rationale**: Optimized, lightweight assembly has no guard rails; differential tests,
fuzzing, partial-I/O coverage, and syscall traces are what make the tools provably solid
rather than merely small and fast.

## UOLT Extras (Non-Core Collection)

The core toolset is POSIX-only (Principle VIII). Some genuinely useful tools are not part of the
POSIX core (e.g. `column`, aligning piped output into a table). Rather than pollute the core or
fork the project, these live in a clearly separated **extras** collection.

- **Location & naming**: extra tools live under `extras/<name>/<name>.S` (the core lives under
  `src/`), and still ship as `uolt-<name>` binaries (e.g. `uolt-column`). They reuse the exact
  same shared infrastructure - `sys/<os>/`, `libuolt/`, `include/uolt.inc`, the entry shim, the
  Linux link script, and the single Makefile - so there is no second copy of anything and no
  drift.
- **What is relaxed**: extras are exempt from Principle VIII (POSIX-only) and only that. They
  MAY implement behavior POSIX does not specify (or does not have a tool for).
- **What still holds**: every other principle applies unchanged - I (assembly only), II (direct
  syscalls), III (zero dependencies), IV (no heap; explicit failure-checked mmap only), V (thin
  syscall abstraction + shared internal API), VI (a declared, held size target), VII (measured
  optimization), IX (readable & explicit), X (documentation + a README entry), and XI (unit,
  fuzz, partial-I/O, and syscall-trace tests, plus a benchmark). Where no reference tool exists
  to diff against, golden-output tests substitute for the differential requirement, and that
  substitution MUST be noted in the tool.
- **Not a dual build**: an extra is NOT a second build of a core tool and NOT a runtime
  "extended mode" flag - both of which Principle VIII forbids because they double the test
  surface and inflate size. Each extra is its own single binary. The core binaries are byte-for-
  byte identical whether or not the extras exist.
- **Scope discipline**: the extras collection is not a licence to chase GNU breadth. A tool
  belongs here only when it is genuinely useful and cannot exist in the POSIX core; each addition
  is reviewed on that bar.

## Platform & Architecture Scope

- **Architecture**: Linux x86_64 and Linux aarch64 (ARM64) are both in-scope. macOS ARM
  (Apple Silicon / arm64 macOS) is deferred; do not target it now (see the direct-syscall note
  below). Architecture is a first-class directory dimension: instruction-level code (entry
  shim, `libuolt/` primitives, tool bodies) is authored per-arch, and the syscall layer nests
  arch under OS because the numbers differ by both.
- **Operating systems**: Linux and macOS, served through the thin per-OS(-and-arch) syscall
  layer of Principle V. All non-syscall logic is shared across OSes; the aarch64 vs x86_64
  syscall-shape divergence (aarch64 drops legacy calls in favor of the `*at` family) is
  absorbed inside `sys/linux/arm64/` so tool bodies and `libuolt/` keep identical internal-API
  signatures across arches. A tool file (e.g. `ls.S`) never contains an OS- or arch-specific
  syscall number.
- **Toolchain**: one assembler across platforms - the clang integrated assembler (`as`),
  x86_64 sources written in Intel syntax via `.intel_syntax noprefix` (readability,
  Principle IX). This choice deliberately keeps a single toolchain that will also cover a
  future arm64 target (NASM would not, being x86-only).
- **macOS direct-syscall note**: on x86_64 macOS, direct syscalls work and are the chosen
  path. On arm64 macOS, Apple restricts direct syscalls (they are expected to originate from
  libSystem); reaching arm64 macOS would require re-deciding Principle II for that target
  (accept fragile direct `svc`, or call libSystem's syscall stubs on that platform only). This
  unresolved tension is why macOS ARM stays deferred while Linux aarch64 (where direct `svc #0`
  is permitted) is in-scope. Recorded so the tension is not forgotten.
- **Layout** (per-OS-and-arch; `<arch>` in {x86_64, arm64}): the syscall wrappers depend on
  both OS and arch (numbers differ by both) so arch nests under OS; `libuolt/` primitives and
  tool bodies depend on arch only (instructions), so arch nests directly:
  ```
  sys/
      linux/  uolt.ld
              x86_64/  start.S  write.S  exit.S  ...
              arm64/   start.S  write.S  exit.S  ...   (*at family absorbed here)
      macos/  x86_64/  ...
  libuolt/
      x86_64/  strlen.S  write.S  ...
      arm64/   strlen.S  write.S  ...
  src/<tool>/
      x86_64/<tool>.S
      arm64/<tool>.S
  extras/<name>/
      x86_64/<name>.S
      arm64/<name>.S
  ```

## Size & Startup Targets

Initial per-tool size targets (evolve with the project; changes require approval):

| tool   | target  |
|--------|---------|
| true   | < 1 Ko  |
| false  | < 1 Ko  |
| pwd    | < 2 Ko  |
| echo   | < 3 Ko  |
| cat    | < 5 Ko  |
| mkdir  | < 5 Ko  |
| rm     | < 6 Ko  |
| ls     | < 12 Ko |

Additional targets:
- All binaries are static with zero dynamic dependencies (Principle III).
- Startup MUST be under 1 millisecond; this is measured.

## Build & Tooling

- The whole project builds with a single command (`make` or `just build`).
- The build MUST be clean: zero assembler warnings.
- Build scripts MAY be written in another language; production code MAY NOT (Principle I).

## Scope Discipline (Roadmap)

Build order, simplest first:

1. `true`, `false`, `echo`, `pwd`, `dirname`, `basename`, `yes`, `sleep`, `touch`, `mkdir`,
   `rmdir`, `rm`, `mv`, `cp`, `cat`, `head`, `tail`, `wc`, `ln`, `chmod`.
2. Then `ls`.
3. Only much later: `find`, `grep`, `sort`, `awk`, `sed` - they are far more complex than they
   appear and MUST NOT be attempted early.

## Development Workflow & Quality Gates

- **Correctness gate**: a change MUST pass the tool's unit, POSIX, regression, differential,
  and fuzz tests, including the partial-I/O edge cases and the syscall-trace check
  (Principle XI).
- **Performance gate**: a change touching a hot path MUST report before/after benchmarks; a
  regression MUST be justified or rejected (Principle VII). Additionally, each tool MUST be at
  least as fast as the standard tool it replaces on Linux x86_64 (`hyperfine`), and should be
  faster; macOS parity within measurement noise is acceptable (Principle XI performance floor).
- **Footprint gate**: a change MUST NOT push a tool past its declared size target without an
  approved target update (Principle VI).
- **Purity gate**: reviewers MUST reject any libc/libgcc/runtime linkage, any heap allocation,
  any dynamic dependency, and any raw syscall number in tool code.
- **Clean-build gate**: the build MUST complete with a single command and zero warnings.
- **Documentation gate**: new or changed options, behaviors, internal API, and every
  optimization MUST be documented in the same change.
- **README gate**: when a command is developed, the README MUST be updated with that
  command's entry (name, binary size, and any other relevant info); a change is incomplete
  without it (Principle X).

## Governance

This constitution supersedes other practices for UOLT. Amendments MUST be proposed as a
documented change, reviewed, and versioned per the policy below. All reviews and pull requests
MUST verify compliance with the applicable principles; any deviation MUST be justified in
writing and either approved or corrected before merge.

**Versioning policy** (semantic):
- **MAJOR**: backward-incompatible removal or redefinition of a principle or governance rule.
- **MINOR**: a new principle or section is added, or guidance is materially expanded.
- **PATCH**: clarifications, wording, or non-semantic refinements.

Compliance is reviewed on every change through the quality gates above. Complexity that
violates a principle MUST be justified or removed.

**Version**: 1.7.0 | **Ratified**: 2026-07-12 | **Last Amended**: 2026-07-16
