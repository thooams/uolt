# Feature Specification: uolt-pwd

**Feature Branch**: `004-uolt-pwd` (built on `main`)  
**Created**: 2026-07-12  
**Status**: Implemented  
**Input**: User description: "pwd"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Print the working directory (Priority: P1)

A user or script needs the absolute path of the current directory. Running `uolt-pwd` prints
that path followed by a newline and exits 0. This is the first UOLT tool that reads state from
the system (the working directory), not just its arguments.

**Independent Test**: from a known directory, `uolt-pwd` prints that directory's absolute path
and exits 0.

**Acceptance Scenarios**:

1. **Given** a working directory, **When** `uolt-pwd`, **Then** stdout is the absolute path +
   newline and exit is 0.
2. **Given** any directory on the system, **When** `uolt-pwd`, **Then** output matches
   `/bin/pwd -P` (the physical path).

### Edge Cases

- Output is always absolute (begins with `/`) and newline-terminated.
- Arguments are ignored (no `-L`/`-P` handling in v1; behavior is physical, like `-P`).
- If the directory cannot be resolved (e.g. it was removed), exit is non-zero.
- macOS case-insensitive filesystems: the reported name is the true on-disk case (via
  `F_GETPATH`), which can differ in case from a path typed with different casing.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: MUST print the absolute pathname of the current working directory.
- **FR-002**: MUST terminate the output with a single newline.
- **FR-003**: Output MUST equal the physical path (`pwd -P`), resolving symlinks.
- **FR-004**: MUST exit `0` on success, non-zero if the directory cannot be resolved.
- **FR-005**: MUST NOT allocate on the heap (uses a stack buffer) and MUST read nothing from
  stdin.
- **FR-006**: MUST record its README entry (name, size) per the constitution.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Output matches `/bin/pwd -P` byte-for-byte from multiple directories (`/`,
  `/tmp`, `/usr`, a temp dir).
- **SC-002**: A syscall trace shows no `mmap`/`brk` (no heap); Linux uses the `getcwd` syscall,
  macOS uses `open`+`fcntl(F_GETPATH)`+`close`.
- **SC-003**: Binary meets a < 2 KB target on Linux (528 B achieved; macOS ~5.5 KB Mach-O
  floor).
- **SC-004**: At least as fast as the system `pwd` on Linux (measured ~1.9× faster).

## Assumptions

- Physical path (`-P` semantics) is the v1 behavior; logical `-L` and option parsing are
  deferred.
- macOS blocks the direct `__getcwd` syscall (raises SIGSYS), so the macOS wrapper resolves the
  path via `open(".")` + `fcntl(F_GETPATH)` + `close`; Linux uses the `getcwd` syscall. The
  tool calls one `sys_getcwd`, unaware of the platform difference (Principle V).
- Adds `libuolt/getcwd.S` and per-OS `sys/<os>/getcwd.S`; reuses the entry shim, `strlen`, and
  `write` from earlier tools.
