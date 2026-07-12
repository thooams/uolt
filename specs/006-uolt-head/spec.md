# Feature Specification: uolt-head

**Feature Branch**: `006-uolt-head` (built on `main`)  
**Created**: 2026-07-12  
**Status**: Implemented  
**Input**: User description: "head"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Show the top of a file (Priority: P1)

A user wants the beginning of a file without reading all of it. They run `uolt-head file`; the
first 10 lines are written to stdout and the tool exits 0. This is the first UOLT tool that
interprets its input (counts newlines) rather than copying it whole.

**Independent Test**: `uolt-head FILE` writes the first 10 lines of FILE and exits 0.

**Acceptance Scenarios**:

1. **Given** a file of more than 10 lines, **When** `uolt-head file`, **Then** stdout is its
   first 10 lines and exit is 0.
2. **Given** a file of fewer than 10 lines, **When** `uolt-head file`, **Then** the whole file
   is written unchanged.
3. **Given** a final line without a trailing newline, **When** it falls within the count, **Then**
   it is written as-is (no newline is added).

---

### User Story 2 - Choose the line count with -n (Priority: P1)

A user needs a specific number of lines. `uolt-head -n 3 file` (or `-n3 file`) writes the first
three lines.

**Independent Test**: `uolt-head -n 3 file` writes exactly the first three lines.

**Acceptance Scenarios**:

1. **Given** `-n 5`, **When** `uolt-head -n 5 file`, **Then** the first five lines are written.
2. **Given** the joined form `-n5`, **When** `uolt-head -n5 file`, **Then** the result is
   identical to `-n 5`.
3. **Given** `-n 0`, **When** `uolt-head -n 0 file`, **Then** nothing is written and exit is 0.

---

### User Story 3 - Multiple files with headers (Priority: P2)

Given several files, `uolt-head` labels each section with a `==> name <==` header and separates
consecutive sections with a blank line, matching the shared GNU/BSD format.

**Independent Test**: `uolt-head -n1 a b` emits `==> a <==`, the first line of `a`, a blank
line, `==> b <==`, then the first line of `b`.

**Acceptance Scenarios**:

1. **Given** two files, **When** `uolt-head a b`, **Then** each is preceded by its header and a
   blank line separates them (no leading blank line before the first).
2. **Given** a nonexistent file among the operands, **When** `uolt-head missing good`, **Then**
   `missing` produces a stderr diagnostic and no header, `good` is still shown, and the exit
   status is nonzero.

---

### Edge Cases

- No operand, or the operand `-`, reads standard input (labelled `standard input` when headed).
- Data is copied byte-transparently within a line (NUL and high bytes survive).
- Large inputs are processed in fixed 64 KB blocks with no heap allocation; short writes are
  drained in a loop.
- `--` ends option processing; a later token is a filename.
- `-n 0` writes no lines (GNU-compatible; BSD instead rejects 0 - see Assumptions).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: MUST write the first N lines of each file operand to stdout, N defaulting to 10.
- **FR-002**: MUST accept `-n number` and the joined `-nnumber`; the last one wins.
- **FR-003**: A line is bytes up to and including a `\n`; a final line without `\n` still counts.
- **FR-004**: With no operand, or the operand `-`, MUST read standard input.
- **FR-005**: With more than one operand, MUST print a `==> name <==` header before each, with a
  blank line between consecutive sections and none before the first.
- **FR-006**: MUST stream through a fixed stack buffer with no heap allocation (Principle IV) and
  drain each write completely (tolerating short writes).
- **FR-007**: On a file that cannot be opened, MUST write a stderr diagnostic (no header),
  continue with the remaining operands, and exit nonzero.
- **FR-008**: MUST exit 0 when every operand (and stdin) was read successfully.
- **FR-009**: MUST record its README entry (name and binary size) per the constitution.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Output matches the reference `head` byte-for-byte across the tested cases (default,
  `-n` joined/separate, short/empty/no-newline files, multi-file headers, stdin), including a
  fuzz comparison over random contents and counts.
- **SC-002**: Exit status agrees with the reference for the tested cases (0 on success, nonzero
  on an unreadable operand).
- **SC-003**: A syscall trace shows only open/read/close and write (plus exit) - no `mmap`/`brk`.
- **SC-004**: Binary meets a < 2 KB target on Linux (1336 B achieved; macOS ~6 KB Mach-O floor).
- **SC-005**: On Linux, at worst as fast as the system `head`; measured ~1.6× faster.

## Assumptions

- Only POSIX option `-n` is implemented; GNU `-c`/`-q`/`-v` and BSD `-C` are out of scope
  (POSIX, not GNU, Principle VIII).
- `-` selects standard input (POSIX/GNU behavior). BSD `head` instead rejects `-`; differential
  tests therefore do not exercise `-`, staying within the BSD/GNU common denominator.
- `-n 0` prints nothing and exits 0 (GNU semantics). BSD `head` treats 0 as an illegal count and
  exits nonzero; fuzz avoids 0 for the same reason.
- Diagnostic wording for a failed open differs from the system tool by design; differential
  tests compare stdout and exit code, not stderr text.
- Reuses the file-I/O primitives added with `uolt-cat` (`open`/`read`/`close`) plus `write`/
  `strlen`; adds no new syscall wrapper.
