# Feature Specification: uolt-chmod

**Feature Branch**: `020-uolt-chmod` (built on `main`)  
**Created**: 2026-07-13  
**Status**: Implemented (octal mode form)  
**Input**: User description: "chmod"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Set permissions (Priority: P1)

`uolt-chmod 755 file` sets the file's permission bits to octal 0755.

**Acceptance Scenarios**:

1. **Given** `755 f`, **When** run, **Then** `f` becomes rwxr-xr-x.
2. **Given** a leading-zero form `0644 f`, **When** run, **Then** `f` becomes rw-r--r--.
3. **Given** several files, **When** `chmod 640 a b`, **Then** both are changed.

---

### Edge Cases

- Special bits are honoured: setuid (4xxx), setgid (2xxx), sticky (1xxx).
- A symbolic mode (u+x, ...) is rejected with a diagnostic (unsupported in v1).
- A missing file, or too few operands, is an error; a failure continues with the rest.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: MUST parse the first operand as an octal mode and apply it to each file operand.
- **FR-002**: MUST honour the full 12-bit mode (special bits + rwx for user/group/other).
- **FR-003**: A non-octal (symbolic) mode MUST be rejected with a diagnostic and exit 1.
- **FR-004**: MUST require a mode and at least one file; a failure sets exit 1 but continues.
- **FR-005**: MUST use no heap (Principle IV).
- **FR-006**: MUST record its README entry (name and binary size) per the constitution.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The resulting permission bits and exit status match the system `chmod` across a
  range of octal modes (644, 755, 600, special bits, leading zeros).
- **SC-002**: Binary meets a < 1 KB target on Linux (816 B achieved; macOS ~5.5 KB floor).

## Assumptions

- Symbolic modes (u/g/o/a with +/-/= and rwx) are out of scope in v1: the relative +/- forms need
  the file's current mode (a stat), which is not yet available. Only octal modes are supported.
- `-R` (recursive) is deferred (needs directory reading). Adds the per-OS `chmod` wrapper; reuses
  `write`/`strlen`.
