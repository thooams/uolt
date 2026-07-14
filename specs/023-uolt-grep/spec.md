# Feature Specification: uolt-grep

**Feature Branch**: `023-uolt-grep` (built on `main`)  
**Created**: 2026-07-13  
**Status**: Implemented (fixed-string, like grep -F)  
**Input**: User description: "grep"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Find matching lines (Priority: P1)

`uolt-grep pattern file` prints the lines of `file` that contain `pattern` as a literal substring.

**Acceptance Scenarios**:

1. **Given** a pattern and file, **When** run, **Then** matching lines print.
2. **Given** no file, **When** input is piped, **Then** standard input is searched.
3. **Given** several files, **When** run, **Then** each matching line is prefixed with "file:".

---

### User Story 2 - Case folding and inversion (Priority: P2)

`-i` matches case-insensitively; `-v` prints the non-matching lines.

---

### Edge Cases

- An empty pattern matches every line.
- A final line without a trailing newline is still matched.
- A line longer than the 64 KB buffer is matched as one truncated piece.
- Exit status follows grep: 0 if any line matched, 1 if none, 2 on error (e.g. an unopenable file
  or a missing pattern operand).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: MUST print input lines that contain the pattern as a literal substring.
- **FR-002**: `-i` MUST fold ASCII case; `-v` MUST print the complement (non-matching lines).
- **FR-003**: With no file operand MUST read standard input; with more than one file MUST prefix
  each matching line with "file:".
- **FR-004**: Exit status MUST be 0 (matched), 1 (no match), or 2 (error).
- **FR-005**: MUST use no heap (Principle IV): input flows through a 64 KB line buffer.
- **FR-006**: MUST record its README entry (name and binary size) per the constitution.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Output and exit status match `grep -F` across the tested cases (basic, -i, -v, -iv,
  no-match, multi-file, substring, spaces, stdin).
- **SC-002**: Binary meets a < 2 KB target on Linux (1448 B achieved; macOS ~7.6 KB floor).

## Assumptions

- This is a fixed-string matcher (like `grep -F`); regular expressions and the many other grep
  options (-n, -c, -l, -r, -w, -x, ...) are out of scope in v1. ASCII case folding only.
- Reuses `open`/`read`/`close`/`write`/`strlen`; adds a naive substring search and a line splitter.
