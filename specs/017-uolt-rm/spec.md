# Feature Specification: uolt-rm

**Feature Branch**: `017-uolt-rm` (built on `main`)  
**Created**: 2026-07-13  
**Status**: Implemented (files + recursive -r)  
**Input**: User description: "rm"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Remove files (Priority: P1)

`uolt-rm f...` removes the named files. A missing file is an error unless `-f` is given.

**Acceptance Scenarios**:

1. **Given** existing files, **When** `rm a b`, **Then** both are removed, exit 0.
2. **Given** a missing file, **When** `rm x`, **Then** it errors (exit 1).
3. **Given** `-f` and a missing file, **When** run, **Then** it is silently ignored, exit 0.

---

### User Story 2 - Remove a directory tree with -r (Priority: P1)

`uolt-rm -r dir` removes `dir` and everything under it.

**Acceptance Scenarios**:

1. **Given** `-r` and a directory tree, **When** run, **Then** the whole tree is removed.
2. **Given** `-r` on a plain file, **When** run, **Then** the file is removed.
3. **Given** a directory without `-r`, **When** run, **Then** it is an error.

### Edge Cases

- Without `-r`, a directory operand is an error; `-f` alone does not remove it.
- No operand is an error, except `rm -f` with no operands, which is a no-op success.
- A failure sets exit 1 but continues with the remaining operands.
- Recursion reuses a single directory buffer and a single path buffer at every level (no heap):
  it re-opens each directory per removal, so no read position is held across the recursion.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: MUST remove each file operand with unlink.
- **FR-002**: With `-f`, MUST silently ignore non-existent operands and make an empty operand list
  a success.
- **FR-003**: With `-r`/`-R` MUST remove directory trees; without it a directory operand is an
  error.
- **FR-004**: A failure (other than a missing file under -f) MUST diagnose and set exit 1, without
  stopping the remaining operands; `--` ends options.
- **FR-005**: MUST use no heap (Principle IV).
- **FR-006**: MUST record its README entry (name and binary size) per the constitution.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Exit status and the resulting tree match the system `rm` across the tested file
  (non-recursive) cases.
- **SC-002**: Binary meets a < 1 KB target on Linux (744 B achieved; macOS ~5.6 KB floor).

## Assumptions

- `-i` (interactive) is not supported. Recursion (added after `ls` provided directory reading)
  reuses `opendir`/`getdents`/`unlink`/`rmdir`; the path buffer is 4 KB and the directory buffer
  32 KB, both on the stack.
- Reuses the `unlink` wrapper from `ln` and the `opendir`/`getdents` primitives from `ls`, plus
  `rmdir` from `rmdir`; reuses `write`/`strlen`.
