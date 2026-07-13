# Feature Specification: uolt-rmdir

**Feature Branch**: `014-uolt-rmdir` (built on `main`)  
**Created**: 2026-07-13  
**Status**: Implemented  
**Input**: User description: "rmdir"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Remove an empty directory (Priority: P1)

`uolt-rmdir d` removes the empty directory `d`; a non-empty or missing directory is an error.

**Acceptance Scenarios**:

1. **Given** an empty directory, **When** `uolt-rmdir d`, **Then** it is removed, exit 0.
2. **Given** a non-empty directory, **When** run, **Then** it errors and is kept.
3. **Given** a missing directory, **When** run, **Then** it errors.

---

### User Story 2 - Remove the ancestor chain with -p (Priority: P2)

`uolt-rmdir -p a/b/c` removes `a/b/c`, then `a/b`, then `a`, stopping at the first ancestor that
is not removable (e.g. non-empty).

**Acceptance Scenarios**:

1. **Given** `-p a/b/c` with all empty, **When** run, **Then** all three are removed.
2. **Given** a non-empty ancestor, **When** run, **Then** removal stops there with an error.

---

### Edge Cases

- A failing operand sets exit status 1 but does not stop the remaining operands.
- `--` ends options; missing operand is an error.
- Trailing slashes on a `-p` path are handled.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: MUST remove each named empty directory; non-empty or missing is an error.
- **FR-002**: With `-p`, MUST remove the directory then its now-empty ancestors, stopping at the
  first that cannot be removed.
- **FR-003**: A failure sets exit 1 but continues with the remaining operands; `--` ends options;
  missing operand is an error.
- **FR-004**: MUST use no heap (Principle IV); the `-p` walk shortens the operand string in place.
- **FR-005**: MUST record its README entry (name and binary size) per the constitution.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Exit status and resulting tree match the system `rmdir` across the tested cases
  (empty, non-empty, missing, multiple, -p chains and stops).
- **SC-002**: Binary meets a < 1 KB target on Linux (848 B achieved; macOS ~5.7 KB floor).

## Assumptions

- `--ignore-fail-on-non-empty` and `-v` are out of scope. `-p` climbs the given path's ancestors
  (matching GNU/BSD, including absolute paths up to a non-empty ancestor).
- Adds the per-OS `rmdir` syscall wrapper; reuses `write`/`strlen` for diagnostics.
