<!--
Sync Impact Report
==================
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
when genuinely necessary and MUST be justified in the change.
**Rationale**: Heap allocation adds size, unpredictability, and failure modes UOLT refuses to
carry.

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
`touch`, `cat`, ...) MUST behave as POSIX expects. The dozens of GNU-only options MAY wait;
supported options and any intentional deviation MUST be documented per tool.
**Rationale**: POSIX is a stable, achievable contract; chasing GNU breadth first would sink
the size and simplicity goals.

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
**Rationale**: Optimized, lightweight assembly has no guard rails; differential tests,
fuzzing, partial-I/O coverage, and syscall traces are what make the tools provably solid
rather than merely small and fast.

## Platform & Architecture Scope

- **Architecture**: x86_64 first and only, initially. ARM (including Apple Silicon / arm64
  macOS) is deferred; do not target it now. Porting comes later and will add an `arch/arm64/`
  path plus a resolution of the direct-syscall question below.
- **Operating systems**: Linux and macOS, served through the thin per-OS syscall layer of
  Principle V. All non-syscall logic is shared across OSes; a tool file (e.g. `ls.asm`) never
  contains an OS-specific syscall number.
- **Toolchain**: one assembler across platforms - the clang integrated assembler (`as`),
  x86_64 sources written in Intel syntax via `.intel_syntax noprefix` (readability,
  Principle IX). This choice deliberately keeps a single toolchain that will also cover a
  future arm64 target (NASM would not, being x86-only).
- **macOS direct-syscall note**: on x86_64 macOS, direct syscalls work and are the chosen
  path. On future arm64 macOS, Apple restricts direct syscalls (they are expected to originate
  from libSystem); reaching arm64 macOS will require re-deciding Principle II for that target
  (accept fragile direct `svc`, or call libSystem's syscall stubs on that platform only). Not
  in scope now; recorded so the tension is not forgotten.
- **Layout example**:
  ```
  sys/
      linux/  write.asm  read.asm  stat.asm
      macos/  write.asm  read.asm  stat.asm
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
  regression MUST be justified or rejected (Principle VII).
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

**Version**: 1.3.0 | **Ratified**: 2026-07-12 | **Last Amended**: 2026-07-12
