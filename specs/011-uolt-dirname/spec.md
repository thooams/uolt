# Feature Specification: uolt-dirname

**Feature Branch**: `011-uolt-dirname` (built on `main`)  
**Created**: 2026-07-13  
**Status**: Implemented  
**Input**: User description: "dirname"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Get the directory part (Priority: P1)

A script needs the directory a path lives in. `uolt-dirname /usr/lib/foo.c` prints `/usr/lib`.

**Independent Test**: `uolt-dirname /a/b/c` prints `/a/b`.

**Acceptance Scenarios**:

1. **Given** a path with directories, **When** run, **Then** everything before the last
   component prints.
2. **Given** a bare name with no slash, **When** `uolt-dirname usr`, **Then** `.` prints.
3. **Given** trailing slashes, **When** `uolt-dirname /a/b/`, **Then** `/a` prints.

---

### Edge Cases

- `/` (or an all-slash string) prints `/`.
- `/a` prints `/`; `a/` prints `.`.
- An empty string prints `.`.
- Interior repeated slashes are preserved in the directory part (`a//b//c` -> `a//b`).
- No operand is an error (stderr diagnostic, nonzero exit).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: MUST strip trailing '/', then print everything up to (not including) the last '/'
  and the separating slash(es).
- **FR-002**: A string with no '/' left (or an empty string) MUST print `.`.
- **FR-003**: A string of only '/', or one whose directory part strips to nothing, MUST print `/`.
- **FR-004**: MUST append a trailing newline.
- **FR-005**: MUST error (stderr + nonzero exit) when no operand is given; extra operands are
  ignored.
- **FR-006**: MUST do no file I/O and no heap allocation (Principle IV).
- **FR-007**: MUST record its README entry (name and binary size) per the constitution.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Output matches the reference `dirname` byte-for-byte across the tested path shapes,
  including a fuzz comparison over random path-like strings.
- **SC-002**: Exit status agrees with the reference.
- **SC-003**: Binary meets a < 1 KB target on Linux (688 B achieved; macOS ~5.4 KB Mach-O floor).
- **SC-004**: On Linux, at worst as fast as the system tool; measured ~1.4× faster (startup-bound).

## Assumptions

- POSIX single-operand form only; GNU `-z` is out of scope in v1.
- The single-operand behavior is where GNU and BSD agree, so it is tested differentially against
  whichever `dirname` is installed.
- Reuses `write`/`strlen`; adds no new syscall. Sibling of `uolt-basename` (same string scan,
  keeping the directory part instead of the last component).
