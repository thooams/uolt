# Feature Specification: uolt-basename

**Feature Branch**: `010-uolt-basename` (built on `main`)  
**Created**: 2026-07-13  
**Status**: Implemented  
**Input**: User description: "basename"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Strip the directory part (Priority: P1)

A script needs the file name out of a path. `uolt-basename /usr/lib/foo.c` prints `foo.c`.

**Independent Test**: `uolt-basename /a/b/c` prints `c`.

**Acceptance Scenarios**:

1. **Given** a path with directories, **When** run, **Then** only the last component prints.
2. **Given** trailing slashes, **When** `uolt-basename /a/b/`, **Then** `b` prints.
3. **Given** an all-slash string, **When** `uolt-basename ///`, **Then** `/` prints.

---

### User Story 2 - Remove a suffix (Priority: P2)

`uolt-basename foo.c .c` prints `foo`: the suffix is removed when the component ends with it.

**Independent Test**: `uolt-basename /d/foo.tar.gz .gz` prints `foo.tar`.

**Acceptance Scenarios**:

1. **Given** a matching suffix, **When** run, **Then** it is removed from the end.
2. **Given** a suffix equal to the whole component, **When** `uolt-basename .c .c`, **Then** `.c`
   prints (not stripped to empty).
3. **Given** a non-matching suffix, **When** run, **Then** the component prints unchanged.

---

### Edge Cases

- An empty string prints an empty line.
- No operand is an error (stderr diagnostic, nonzero exit).
- The result is written directly from the operand's bytes; no buffer, no file access.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: MUST remove trailing '/' characters, then print the substring after the last '/'.
- **FR-002**: A string of only '/' MUST print a single '/'.
- **FR-003**: An empty string MUST print an empty line.
- **FR-004**: With a suffix operand, MUST remove it from the end of the component unless it equals
  the whole component.
- **FR-005**: MUST append a trailing newline.
- **FR-006**: MUST error (stderr + nonzero exit) when no operand is given; extra operands beyond
  string and suffix are ignored.
- **FR-007**: MUST do no file I/O and no heap allocation (Principle IV).
- **FR-008**: MUST record its README entry (name and binary size) per the constitution.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Output matches the reference `basename` byte-for-byte across the tested path shapes
  and suffix cases, including a fuzz comparison over random path-like strings.
- **SC-002**: Exit status agrees with the reference.
- **SC-003**: Binary meets a < 1 KB target on Linux (728 B achieved; macOS ~5.4 KB Mach-O floor).
- **SC-004**: On Linux, at worst as fast as the system tool; measured ~1.4× faster (startup-bound,
  like `true`).

## Assumptions

- POSIX one/two-operand form only; GNU `-a`/`-s`/`-z` are out of scope in v1.
- The one/two-operand behavior is where GNU and BSD agree, so it is tested differentially against
  whichever `basename` is installed.
- Reuses `write`/`strlen`; adds no new syscall. Suffix matching is an inline byte compare.
