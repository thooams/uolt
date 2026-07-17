---
description: "Task list for the Linux aarch64 (ARM64) port"
---

# Tasks: Linux aarch64 (ARM64) Port

**Input**: Design documents from `/specs/035-aarch64-port/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/internal-api.md

**Tests**: The project's constitution (Principle XI) mandates unit/POSIX/differential/fuzz/trace for
every tool. Those suites ALREADY EXIST and are arch-agnostic; porting a tool = making its existing
suite pass on aarch64 (under qemu in CI). No new test scaffolding is written per tool; "pass its
suite" is the acceptance step, not a separate authoring task.

**Organization**: By user story. US1 = thin slice (MVP), US2 = whole suite, US3 = CI guard.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: parallelizable (different files, no incomplete dependency)
- **[Story]**: US1 / US2 / US3 for story-phase tasks; Setup/Foundational/Polish carry no label
- Paths are repo-relative.

## Path Conventions

Sub-directory-per-arch (plan.md Structure Decision): `sys/linux/<arch>/`, `libuolt/<arch>/`,
`src/<tool>/<arch>/`, `extras/<name>/<arch>/`. `<arch>` ∈ {`x86_64`, `arm64`}.

---

## Phase 1: Setup (Shared Infrastructure) — blocking

**Purpose**: Governance, the one-time x86_64 migration, and arch-aware build. Nothing aarch64 can be
built until the tree is arch-shaped and the build selects by arch.

- [X] T001 Amend the constitution v1.6.0 → v1.7.0: move **Linux aarch64** from deferred to in-scope in "Platform & Architecture Scope", record the per-OS-and-arch layout (`sys/linux/<arch>/`, `libuolt/<arch>/`, `src/<t>/<arch>/`), keep **macOS ARM deferred** (direct-syscall tension). File: `.specify/memory/constitution.md` (GOVERNANCE GATE, FR-015 — blocks all implementation).
- [X] T002 Migrate x86_64 sources into `x86_64/` subdirs via `git mv` (no logic change): `sys/linux/*.S` → `sys/linux/x86_64/`, `libuolt/*.S` → `libuolt/x86_64/`, `src/<t>/<t>.S` → `src/<t>/x86_64/<t>.S` for all 35 tools, `extras/column/column.S` → `extras/column/x86_64/column.S`. Keep `sys/linux/uolt.ld` at `sys/linux/`.
- [X] T003 Make the Makefile arch-aware in `Makefile`: `ARCH := $(shell uname -m)` normalized (`aarch64|arm64→arm64`, `x86_64|amd64→x86_64`), overridable via `ARCH=`; unknown arch → hard error (FR-012); set `SYSDIR := sys/linux/$(ARCH)`, `LIBDIR := libuolt/$(ARCH)`, tool source `src/<t>/$(ARCH)/<t>.S` and extra `extras/<n>/$(ARCH)/<n>.S`; pass `-target <triple>` and `-DUOLT_ARCH_X86_64|-DUOLT_ARCH_ARM64`. Update `COMMON` and every `EXTRA_<name>` to use `$(LIBDIR)`/`$(SYSDIR)` (basenames unchanged).
- [X] T004 Add the assembler-dialect guard in `include/uolt.inc`: emit `.intel_syntax noprefix` only under `UOLT_ARCH_X86_64` (research D5). Keep the shared `.set` constants and the `DIRENT_*`/`DT_*`/`S_IF*`/`R_OK|W_OK|X_OK` blocks shared (research D4).
- [X] T005 Move `struct stat` field offsets out of shared scope (research D3): define `ST_MODE_OFF`/`ST_SIZE_OFF` per arch (x86_64: 24/48). Place in the arch libuolt/sys layer or an arch-guarded block; remove any shared hardcoded stat offset from `libuolt/x86_64/statmode.S`, `lstatmode.S`, `statsize.S`.
- [X] T006 Regression gate (SC-005): build and run the full suite on x86_64 after T002–T005 — `make ARCH=x86_64 && make test`. Binaries must stay byte-identical (same sources/flags, paths only moved). Do not proceed to Phase 2 until green.

**Checkpoint**: tree is arch-shaped, x86_64 unchanged and green, build selects by arch.

---

## Phase 2: Foundational (aarch64 scaffolding) — blocks every aarch64 body

**Purpose**: The minimum aarch64 chain to build and run ANY tool: entry shim, exit path, link-script
validation, and the qemu execution environment. Per research D9 this de-risks the toolchain before
body work.

- [X] T007 [P] aarch64 entry shim `sys/linux/arm64/start.S`: kernel entry (`[sp]`=argc, `sp+8`=argv) → `uolt_main(x0=argc, x1=argv)` → `uolt_exit(x0=status)`; AArch64 syntax, `svc #0` not used here (pure calls).
- [X] T008 [P] aarch64 exit path: `sys/linux/arm64/exit.S` (exit_group=94 / exit=93, num in `x8`, `svc #0`) and `libuolt/arm64/exit.S` (tail-branch `b sys_exit`). Completes COMMON for arm64.
- [X] T009 Validate the link script on aarch64 (research D6): build a trivial arm64 unit with `sys/linux/uolt.ld` (base 0x400000, single R+X PT_LOAD, `.bss` discarded); if it fails to load/run under qemu, fork `sys/linux/uolt-arm64.ld` and select it in the Makefile. Record the outcome in research.md D6.
- [X] T010 Add qemu execution to the container: `docker/linux-toolchain.Dockerfile` installs `qemu-user-static` + `binfmt-support`; document `binfmt --reset` registration in `quickstart.md` (already drafted) and verify `qemu-aarch64-static build/uolt-<x>` runs.

**Checkpoint**: an aarch64 `_start`+`exit`-only binary builds, links static, and runs under qemu.

---

## Phase 3: User Story 1 — Thin slice on ARM64 (Priority: P1) 🎯 MVP

**Goal**: `true`, `false`, `echo` build and run correctly as static aarch64 ELFs with differential
parity, and the whole chain is green in CI. Proves entry shim + syscall layer + internal API + one
non-trivial body + build selection + CI.

**Independent test**: `make ARCH=arm64` then under qemu: `true`/`false` exit 0/1; `echo -n a b c`
byte-matches `printf '%s' 'a b c'`; `file` reports static aarch64; existing echo/true/false suites pass.

- [X] T011 [P] [US1] aarch64 `libuolt/arm64/strlen.S`, `libuolt/arm64/write.S`, and `sys/linux/arm64/write.S` (write=64) — the `echo` dependency set, symbols/signatures per contracts/internal-api.md.
- [X] T012 [P] [US1] aarch64 body `src/true/arm64/true.S` (return EXIT_SUCCESS).
- [X] T013 [P] [US1] aarch64 body `src/false/arm64/false.S` (return EXIT_FAILURE).
- [X] T014 [US1] aarch64 body `src/echo/arm64/echo.S`: mirror the x86_64 algorithm (leading `-n`, single-space separators, trailing newline), callee-saved regs across `uolt_write`/`uolt_strlen`, rodata `sp_char`/`nl_char` reached by PC-relative load. Depends on T011.
- [X] T015 [US1] Add the `linux-arm64` CI matrix entry in `.github/workflows/ci.yml`: x86_64 runner + qemu-user (binfmt), `make ARCH=arm64`, report `file`/size of `uolt-true`, run the slice tests. Keep `linux-x86_64` unchanged.
- [X] T016 [US1] Slice acceptance (SC-006): under qemu run `true`/`false` exit codes, `echo` differential vs system, `make test` limited to `true`/`false`/`echo`; confirm static + within size discipline. Gate before Phase 4.

**Checkpoint**: MVP — ARM64 toolset demonstrably works for the slice, green in CI, x86_64 untouched.

---

## Phase 4: User Story 2 — Whole-suite parity on ARM64 (Priority: P2)

**Goal**: all 35 core tools + `column` run on aarch64 with full test parity. Depends on US1's proven
chain. Organized as: (4a) the remaining aarch64 syscall wrappers + libuolt primitives, then (4b)
per-tool bodies in constitution build order (simplest first), each passing its existing suite.

### Phase 4a: Remaining aarch64 syscall wrappers + libuolt primitives (shared, blocks bodies)

Each wrapper owns one number and absorbs `AT_FDCWD`/flags per research D2; each libuolt primitive
mirrors its x86_64 sibling with identical symbol/signature (contracts/internal-api.md).

- [X] T017X [P] [US2] I/O + fd wrappers `sys/linux/arm64/`: `read.S` (63), `close.S` (57), `lseek.S` (62); libuolt `read.S`, `close.S`, `lseek.S`.
- [X] T018X [P] [US2] Memory wrappers `sys/linux/arm64/mmap.S` (222), `munmap.S` (215); libuolt `mmap.S` (anon RW private, zero-filled), `munmap.S`.
- [X] T019X [P] [US2] `openat` shim `sys/linux/arm64/open.S` (56, dirfd=AT_FDCWD) + variants `openapp.S`, `opendst.S`, `create.S`; libuolt counterparts. Preserve the exact flags/mode the x86_64 `open`/`openapp`/`opendst`/`create` present.
- [X] T020 [P] [US2] Directory wrappers `sys/linux/arm64/opendir.S` (openat) + `getdents.S` (getdents64=61); libuolt `opendir.S`, `getdents.S`. `linux_dirent64` layout unchanged (research D4).
- [X] T021 [P] [US2] Path-mutation `*at` wrappers `sys/linux/arm64/`: `mkdir.S` (mkdirat 34), `rmdir.S` (unlinkat 35 | AT_REMOVEDIR 0x200), `unlink.S` (unlinkat 35, flags 0), `rename.S` (renameat 38), `link.S` (linkat 37), `symlink.S` (symlinkat 36); libuolt counterparts (signatures unchanged).
- [X] T022 [P] [US2] Metadata wrappers `sys/linux/arm64/`: `chmod.S` (fchmodat 53), `access.S` (faccessat 48), `statmode.S`/`lstatmode.S` (newfstatat 79, flags 0 / AT_SYMLINK_NOFOLLOW 0x100), `statsize.S` (newfstatat 79), `umask.S`; libuolt counterparts using arch `ST_MODE_OFF`/`ST_SIZE_OFF` (T005). Define arm64 `ST_MODE_OFF=16`, `ST_SIZE_OFF=48`.
- [X] T023 [P] [US2] Process/time wrappers `sys/linux/arm64/`: `execve.S` (221), `utimes.S` (utimensat 88 + timeval→timespec conversion), `sleep.S` (nanosleep 101), `getcwd.S` (17); libuolt counterparts.

### Phase 4b: aarch64 tool bodies (constitution build order, simplest first)

Each task = author `src/<t>/arm64/<t>.S` mirroring the x86_64 algorithm + make its existing suite
pass under qemu. All are [P] w.r.t. each other (distinct files) once 4a lands.

- [X] T024 [P] [US2] `src/pwd/arm64/pwd.S` + pass suite (getcwd, write).
- [X] T025 [P] [US2] `src/yes/arm64/yes.S` + pass suite.
- [X] T026 [P] [US2] `src/basename/arm64/basename.S` + pass suite.
- [X] T027 [P] [US2] `src/dirname/arm64/dirname.S` + pass suite.
- [X] T028 [P] [US2] `src/seq/arm64/seq.S` + pass suite (arithmetic: `sdiv`/`msub` for the x86 `div`).
- [X] T029 [P] [US2] `src/sleep/arm64/sleep.S` + pass suite (nanosleep).
- [X] T030 [P] [US2] `src/env/arm64/env.S` + pass suite (execve).
- [X] T031 [P] [US2] `src/printf/arm64/printf.S` + pass suite (format engine; arch arithmetic).
- [X] T032 [P] [US2] `src/expr/arm64/expr.S` + pass suite (arithmetic; `sdiv`/`msub`).
- [X] T033 [P] [US2] `src/test/arm64/test.S` + pass suite (stat/lstat/access; verify arch stat offsets via file-type tests).
- [X] T034 [P] [US2] `src/cat/arm64/cat.S` + pass suite (open/read/write/close).
- [X] T035 [P] [US2] `src/head/arm64/head.S` + pass suite.
- [X] T036 [P] [US2] `src/wc/arm64/wc.S` + pass suite (counting; arch arithmetic).
- [X] T037 [P] [US2] `src/cut/arm64/cut.S` + pass suite.
- [X] T038 [P] [US2] `src/tr/arm64/tr.S` + pass suite.
- [X] T039 [P] [US2] `src/comm/arm64/comm.S` + pass suite.
- [X] T040 [P] [US2] `src/tee/arm64/tee.S` + pass suite (opendst/openapp).
- [X] T041 [P] [US2] `src/grep/arm64/grep.S` + pass suite.
- [X] T042 [P] [US2] `src/uniq/arm64/uniq.S` + pass suite (mmap slurp).
- [X] T043 [P] [US2] `src/sort/arm64/sort.S` + pass suite (growable mmap; failure-checked).
- [X] T044 [P] [US2] `src/tail/arm64/tail.S` + pass suite (lseek/mmap; 64 KB pipe cap).
- [X] T045 [P] [US2] `src/mkdir/arm64/mkdir.S` + pass suite (mkdirat, chmod, umask).
- [X] T046 [P] [US2] `src/rmdir/arm64/rmdir.S` + pass suite (unlinkat|AT_REMOVEDIR).
- [X] T047 [P] [US2] `src/touch/arm64/touch.S` + pass suite (create, utimensat).
- [X] T048 [P] [US2] `src/ln/arm64/ln.S` + pass suite (linkat/symlinkat/unlinkat/stat).
- [X] T049 [P] [US2] `src/rm/arm64/rm.S` + pass suite (unlinkat, getdents recursion, rmdir).
- [X] T050 [P] [US2] `src/mv/arm64/mv.S` + pass suite (renameat, stat).
- [X] T051 [P] [US2] `src/cp/arm64/cp.S` + pass suite (open/read/getdents/mkdir/stat).
- [X] T052 [P] [US2] `src/chmod/arm64/chmod.S` + pass suite (fchmodat, stat, umask).
- [X] T053 [P] [US2] `src/ls/arm64/ls.S` + pass suite (opendir/getdents64).
- [X] T054 [P] [US2] `src/find/arm64/find.S` + pass suite (getdents recursion, `-maxdepth`).
- [X] T055 [P] [US2] `extras/column/arm64/column.S` + pass suite (mmap slurp, two-pass width; extra).
- [X] T056 [US2] Full aarch64 suite green: `make ARCH=arm64 && make test` (all layers, all tools) under qemu; every tool byte-for-byte vs system in the differential agreement zone (SC-002/SC-003). Confirm each binary static + within size discipline (SC-004). Result: 92 PASS, 11 trace SKIP, 0 FAIL; all static.

**Checkpoint**: whole suite runs on aarch64 with full parity.

---

## Phase 5: User Story 3 — ARM64 guarded by CI (Priority: P3)

**Goal**: CI exercises the full aarch64 build+test and fails independently of x86_64.

- [X] T057 [US3] Extend the `linux-arm64` CI job (T015) in `.github/workflows/ci.yml` to run the FULL `make test` (not just the slice) and report the arm64 `uolt-true` size, matching the x86_64 job's steps.
- [ ] T058 [US3] Verify fail-independence (SC-007): introduce a temporary aarch64-only break on a scratch branch, confirm the arm64 job fails while x86_64 passes, then revert. Record the check in the PR description.
- [X] T059 [US3] Document the trace-layer qemu caveat (research D8): mark the aarch64 trace tests environment-skipped with a recorded reason under qemu, or run them if native; ensure the no-heap structural guarantee is noted. (CI + local harness skip `tests/trace/*` with the recorded reason; no-heap noted as structural.)

**Checkpoint**: aarch64 is a first-class, protected CI target.

---

## Phase 6: Polish & Cross-Cutting

- [X] T060 [P] Update `README.md`: add an aarch64 size per tool (byte counts differ from x86_64 by encoding; discipline held, FR-013/SC-004). (Dual-arch badge/headline, aarch64 suite size note ~51 KB, install line, extras size.)
- [X] T061 [P] Note aarch64 specifics (the `*at` absorption, stat-offset divergence) in each affected tool's `specs/00N-uolt-<tool>/` where materially different, and in the syscall-wrapper comments (Principle X). (aarch64 body headers note arch arithmetic/divergence; the `*at`/stat-offset absorption lives in the Phase-4a syscall wrappers.)
- [X] T062 Update the project-state memory (`uolt-project-state.md`) with the arch dimension, the layout, the syscall-mapping + stat-offset gotchas, and the qemu-CI decision.

---

## Dependencies & Execution Order

- **Phase 1 (Setup)** blocks everything. T001 (constitution) is the governance gate; T002→T003→T004/T005 sequential (same tree/Makefile/header); T006 gates Phase 2.
- **Phase 2 (Foundational)** blocks all aarch64 bodies. T007/T008 [P]; T009 after a buildable unit exists; T010 [P].
- **US1 (Phase 3)** depends on Phase 2. T011 blocks T014; T012/T013/T011 [P]; T015 after bodies build; T016 gates Phase 4.
- **US2 (Phase 4)**: 4a (T017–T023) all [P] with each other, depend on Phase 2 + the T005 stat-offset split. 4b (T024–T055) all [P] with each other, each depends only on the 4a wrappers it uses. T056 gates the phase.
- **US3 (Phase 5)** depends on US2 (full suite must exist to run in CI). T057→T058→T059.
- **Polish (Phase 6)** last; T060/T061 [P].

Story independence: US1 is a standalone MVP (deliverable/demoable alone). US2 depends on US1's proven
chain. US3 depends on US2. This is intentional (a port is inherently layered), not accidental coupling.

## Parallel Opportunities

- Phase 2: T007, T008, T010 together.
- US1: T011, T012, T013 together (T014 waits on T011).
- US2 4a: T017–T023 together (7 wrapper batches).
- US2 4b: T024–T055 together (32 tool bodies) once 4a lands — the largest parallel front.
- Polish: T060, T061 together.

## Implementation Strategy

1. **MVP = Phase 1 + Phase 2 + US1 (T001–T016)**. Delivers a working, CI-green ARM64 slice and proves
   the entire toolchain. Stop-and-review point.
2. **Incremental**: US2 4a (wrappers) as one wave, then fan out 4b bodies simplest-first, each landing
   independently behind its own passing suite. `ls`/`find` and the mmap tools (`sort`/`uniq`/`tail`)
   are the higher-risk bodies — schedule after the simple ones prove the pattern.
3. **Guard**: US3 locks CI so later core-tool work can't silently regress aarch64.

**Total tasks**: 62. US1: 6 (T011–T016). US2: 40 (T017–T056). US3: 3. Setup 6, Foundational 4, Polish 3.
