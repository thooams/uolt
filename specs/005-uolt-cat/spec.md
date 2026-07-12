# Feature Specification: uolt-cat

**Feature Branch**: `005-uolt-cat` (built on `main`)  
**Created**: 2026-07-12  
**Status**: Implemented  
**Input**: User description: "cat"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Print a file to stdout (Priority: P1)

A user or script needs to see the contents of a file. They run `uolt-cat notes.txt`; every
byte of the file is written to stdout, unchanged, and the tool exits 0. This is the first UOLT
tool that opens files and reads their contents.

**Independent Test**: `uolt-cat FILE` writes FILE byte-for-byte to stdout and exits 0.

**Acceptance Scenarios**:

1. **Given** a readable file, **When** `uolt-cat file`, **Then** stdout is the file's exact
   bytes and exit is 0.
2. **Given** several files, **When** `uolt-cat a b c`, **Then** their contents are written in
   operand order with nothing inserted between them.
3. **Given** an empty file, **When** `uolt-cat empty`, **Then** stdout is empty and exit is 0.

---

### User Story 2 - Copy standard input (Priority: P1)

A user pipes data through `cat` or uses it interactively. With no file operands, or with the
operand `-`, `uolt-cat` copies standard input to standard output.

**Independent Test**: `printf 'hi\n' | uolt-cat` writes `hi\n` to stdout and exits 0.

**Acceptance Scenarios**:

1. **Given** no operands, **When** input is piped to `uolt-cat`, **Then** it is copied verbatim
   to stdout.
2. **Given** the operand `-`, **When** `uolt-cat file -`, **Then** the file is written, then
   standard input, in that order.

---

### User Story 3 - Report an unreadable operand (Priority: P2)

A user names a file that cannot be opened. `uolt-cat` writes a diagnostic to stderr, sets a
nonzero exit status, and still processes the remaining operands.

**Independent Test**: `uolt-cat missing good` writes a stderr diagnostic, emits `good`'s
contents to stdout, and exits nonzero.

**Acceptance Scenarios**:

1. **Given** a nonexistent operand, **When** `uolt-cat missing`, **Then** stderr is nonempty,
   stdout is empty, and exit is nonzero.
2. **Given** a bad operand followed by a good one, **When** `uolt-cat missing good`, **Then**
   `good` is still written and the exit status is nonzero.

---

### Edge Cases

- Binary data (NUL bytes, high bytes) is copied verbatim; the tool is byte-transparent.
- Large inputs are copied in fixed 64 KB blocks with no heap allocation.
- A short `write` (e.g. to a full pipe) is drained in a loop so no bytes are dropped.
- `-u` (the only POSIX option) is accepted and ignored: output is already unbuffered.
- A file with no trailing newline is copied as-is (no newline is added).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: MUST write the bytes of each file operand to stdout, in order, unchanged.
- **FR-002**: With no operands, or for the operand `-`, MUST copy standard input to stdout.
- **FR-003**: MUST be byte-transparent (no line, encoding, or escape transformation).
- **FR-004**: MUST move data through a fixed stack buffer with no heap allocation (Principle IV).
- **FR-005**: MUST drain each read chunk to stdout completely, tolerating short writes.
- **FR-006**: MUST accept and ignore the `-u` option (POSIX; already unbuffered).
- **FR-007**: On a file that cannot be opened, MUST write a diagnostic to stderr, continue with
  the remaining operands, and exit with a nonzero status.
- **FR-008**: MUST exit 0 when every operand (and stdin) was read successfully.
- **FR-009**: MUST record its README entry (name and binary size) per the constitution.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Output matches the reference `/bin/cat` byte-for-byte across the tested cases
  (single/multiple files, empty, stdin, `-`, large/binary), including a fuzz comparison over
  random file contents and counts.
- **SC-002**: Exit status agrees with the reference `cat` (0 on success, nonzero when an
  operand cannot be opened).
- **SC-003**: A syscall trace shows only open/read/close and write (plus exit) - no `mmap` or
  `brk` (no heap).
- **SC-004**: Binary meets a < 2 KB target on Linux (824 B achieved; macOS ~6 KB Mach-O floor,
  per the size note in README).
- **SC-005**: On Linux, at worst as fast as the system `cat`; measured ~1.7× faster.

## Assumptions

- POSIX `cat` defines a single option, `-u`; because UOLT issues direct read/write syscalls
  with no stdio buffering, output is inherently unbuffered, so `-u` is a no-op.
- Diagnostic wording for a failed open differs from the system tool by design; differential
  tests compare stdout and exit code, not stderr text.
- Reuses all scaffolding; adds `libuolt` `read`/`open`/`close` and the matching per-OS syscall
  wrappers, alongside the existing `write`/`strlen`. macOS wrappers normalize the BSD carry-flag
  error convention to a negative return so tool code branches on sign uniformly across OSes.
