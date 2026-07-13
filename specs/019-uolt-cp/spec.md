# Feature Specification: uolt-cp

**Feature Branch**: `019-uolt-cp` (built on `main`)  
**Created**: 2026-07-13  
**Status**: Implemented (two-operand file form)  
**Input**: User description: "cp"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Copy a file (Priority: P1)

`uolt-cp source target` copies the contents of `source` into `target`, creating or truncating it.

**Acceptance Scenarios**:

1. **Given** two operands, **When** `cp a b`, **Then** `b` is a byte-for-byte copy of `a` and
   `a` remains.
2. **Given** an existing target, **When** run, **Then** it is truncated and overwritten.
3. **Given** a large/binary source, **When** run, **Then** the copy is byte-identical.

---

### Edge Cases

- An empty source produces an empty target.
- A missing source, a directory target, or the wrong operand count is an error.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: MUST copy the source's bytes to the target, creating it or truncating an existing
  one, through a fixed 64 KB stack buffer (no heap, Principle IV).
- **FR-002**: MUST require exactly two operands; `--` ends options; other counts are a usage error.
- **FR-003**: On failure MUST write a diagnostic and exit 1.
- **FR-004**: MUST record its README entry (name and binary size) per the constitution.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Exit status and the resulting file content match the system `cp` across the tested
  two-operand regular-file cases (basic, overwrite, empty, large).
- **SC-002**: Binary meets a < 1 KB target on Linux (952 B achieved; macOS ~6.3 KB floor).

## Assumptions

- `-r`/`-R` (recursive), copying into a directory (`cp src... dir`), same-file detection (needs
  stat), and permission/timestamp preservation are out of scope in v1. The target gets 0666 masked
  by the umask, which matches a default-mode source.
- Adds the per-OS `opendst` primitive (open O_WRONLY|O_CREAT|O_TRUNC - the O_TRUNC flag differs by
  OS); reuses `open`/`read`/`write`/`close`/`strlen`.
