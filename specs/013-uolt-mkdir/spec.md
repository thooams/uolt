# Feature Specification: uolt-mkdir

**Feature Branch**: `013-uolt-mkdir` (built on `main`)  
**Created**: 2026-07-13  
**Status**: Implemented  
**Input**: User description: "mkdir"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Create a directory (Priority: P1)

`uolt-mkdir newdir` creates `newdir` and exits 0; if it already exists, or its parent is
missing, it is an error.

**Acceptance Scenarios**:

1. **Given** a valid name, **When** `uolt-mkdir d`, **Then** `d` is created, exit 0.
2. **Given** an existing target, **When** run, **Then** it errors (exit 1).
3. **Given** a missing parent (no -p), **When** run, **Then** it errors and nothing is created.

---

### User Story 2 - Create parents with -p (Priority: P1)

`uolt-mkdir -p a/b/c` creates every missing directory in the path and is not an error if the
target already exists.

**Acceptance Scenarios**:

1. **Given** `-p a/b/c`, **When** run, **Then** all of `a`, `a/b`, `a/b/c` exist.
2. **Given** `-p` on an existing directory, **When** run, **Then** exit is 0.

---

### Edge Cases

- The created mode is 0777 masked by the umask (usually 0755).
- `--` ends option processing (a directory may be named `-p`).
- Repeated or trailing slashes in a `-p` path are handled.
- Multiple operands are each attempted; a failure sets the exit status but does not stop the rest.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: MUST create each operand directory with mode 0777 (umask applied by the kernel).
- **FR-002**: With `-p`, MUST create missing parent directories and treat an existing target as
  success.
- **FR-003**: Without `-p`, an existing target or a missing parent MUST be an error.
- **FR-004**: MUST support `--` to end options; missing operand is an error.
- **FR-005**: A failure on one operand MUST set exit status 1 but continue with the others.
- **FR-006**: MUST use no heap (Principle IV); the `-p` walk edits the operand string in place.
- **FR-007**: MUST record its README entry (name and binary size) per the constitution.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Exit status and the resulting directory tree match the system `mkdir` across the
  tested cases (single, multiple, missing parent, -p chains, existing).
- **SC-002**: The default mode honours the umask (0755 under umask 022, 0700 under 077).
- **SC-003**: Binary meets a < 1 KB target on Linux (856 B achieved; macOS ~5.7 KB floor).

## Assumptions

- `-m` (explicit mode) is out of scope in v1; only `-p` and the default umask-based mode are
  supported (POSIX-minimal, Principle VIII).
- Adds the per-OS `mkdir` syscall wrapper; reuses `write`/`strlen` for diagnostics.
