# Feature Specification: uolt-touch

**Feature Branch**: `015-uolt-touch` (built on `main`)  
**Created**: 2026-07-13  
**Status**: Implemented  
**Input**: User description: "touch"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Create or stamp a file (Priority: P1)

`uolt-touch f` creates `f` empty if missing, or updates its access and modification times to now
if it exists, then exits 0.

**Acceptance Scenarios**:

1. **Given** a missing file, **When** run, **Then** it is created empty.
2. **Given** an existing file, **When** run, **Then** its mtime advances and its content is
   unchanged.

---

### User Story 2 - Skip creation with -c (Priority: P2)

`uolt-touch -c f` updates `f` if it exists but does not create it if missing (and that is not an
error).

**Acceptance Scenarios**:

1. **Given** `-c` and a missing file, **When** run, **Then** nothing is created, exit 0.
2. **Given** `-c` and an existing file, **When** run, **Then** its mtime advances.

---

### Edge Cases

- `-a` and `-m` are accepted and ignored (both times are always set to now).
- `--` ends options; a missing operand is an error.
- Multiple operands are each processed; a failure sets exit 1 but continues.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: MUST set both the access and modification times of each operand to the current
  time, creating an empty file if missing (unless -c).
- **FR-002**: With `-c`, MUST not create a missing file and MUST not treat that as an error.
- **FR-003**: MUST accept and ignore `-a`/`-m`; `--` ends options; missing operand is an error.
- **FR-004**: A failure sets exit 1 but continues with the remaining operands.
- **FR-005**: MUST use no heap (Principle IV).
- **FR-006**: MUST record its README entry (name and binary size) per the constitution.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Exit status and file existence match the system `touch` across the tested cases
  (create, existing, -c missing/existing, multiple).
- **SC-002**: An existing file's mtime advances and its content is preserved.
- **SC-003**: Binary meets a < 1 KB target on Linux (912 B achieved; macOS ~6.2 KB floor).

## Assumptions

- `-r` (reference file) and `-t`/`-d` (explicit time) are out of scope in v1; both times are
  always set to now, which makes `-a`/`-m` no-ops.
- Adds two per-OS primitives: `create` (open O_WRONLY|O_CREAT - the O_CREAT flag value differs
  by OS) and `utimes` (set times, NULL = now). Reuses `close`/`write`/`strlen`.
