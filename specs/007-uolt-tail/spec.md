# Feature Specification: uolt-tail

**Feature Branch**: `007-uolt-tail` (built on `main`)  
**Created**: 2026-07-13  
**Status**: Implemented  
**Input**: User description: "tail"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Show the end of a file (Priority: P1)

A user wants the last lines of a log or file. They run `uolt-tail file`; the last 10 lines are
written to stdout and the tool exits 0. On a regular file this is found by seeking, so a huge
file is as cheap as a small one.

**Independent Test**: `uolt-tail FILE` writes the last 10 lines of FILE and exits 0.

**Acceptance Scenarios**:

1. **Given** a file of more than 10 lines, **When** `uolt-tail file`, **Then** stdout is its
   last 10 lines and exit is 0.
2. **Given** a file of fewer than 10 lines, **When** `uolt-tail file`, **Then** the whole file
   is written unchanged.
3. **Given** a final line without a trailing newline, **When** it is within the window, **Then**
   it is written as-is.

---

### User Story 2 - Choose the count with -n, or a start line with -n +N (Priority: P1)

`uolt-tail -n 3 file` writes the last three lines. `uolt-tail -n +5 file` instead writes from
line 5 to the end.

**Independent Test**: `uolt-tail -n 3 file` writes the last three lines; `uolt-tail -n +5 file`
writes from line 5 onward.

**Acceptance Scenarios**:

1. **Given** `-n 5`, **When** `uolt-tail -n 5 file`, **Then** the last five lines are written.
2. **Given** the joined `-n5`, **When** run, **Then** the result equals `-n 5`.
3. **Given** `-n +N`, **When** run, **Then** output starts at line N and runs to the end.
4. **Given** `-n 0`, **When** run, **Then** nothing is written and exit is 0.

---

### User Story 3 - Standard input and multiple files (Priority: P2)

With no operand, or `-` (implicitly), `uolt-tail` reads standard input. Given several files, each
is preceded by a `==> name <==` header with a blank line between sections.

**Independent Test**: `printf 'a\nb\nc\n' | uolt-tail -n1` writes `c`.

**Acceptance Scenarios**:

1. **Given** no operand and piped input, **When** run, **Then** the last N lines of the stream
   are written.
2. **Given** two files, **When** `uolt-tail a b`, **Then** each is preceded by its header.
3. **Given** an unreadable operand among others, **When** run, **Then** it yields a stderr
   diagnostic (no header), the others are still shown, and the exit status is nonzero.

---

### Edge Cases

- Regular files use `lseek(SEEK_END)` + backward block scan; cost tracks the output size.
- Non-seekable input (pipe/stdin) streams through a sliding window that keeps only the last
  64 KB; if the last N lines exceed 64 KB the output is capped there (a no-heap limit).
- Data is byte-transparent within a line (NUL and high bytes survive).
- `--` ends option processing.
- A trailing newline at EOF is not counted as an extra empty line.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: MUST write the last N lines of each file operand, N defaulting to 10.
- **FR-002**: MUST accept `-n number`, the joined `-nnumber`, and the `-n +number` start form.
- **FR-003**: A line ends at `\n`; a final line without `\n` still counts. `-n 0` writes nothing.
- **FR-004**: With no operand, or the operand `-`, MUST read standard input.
- **FR-005**: With more than one operand, MUST print `==> name <==` headers with blank-line
  separators (none before the first).
- **FR-006**: MUST use no heap (Principle IV): backward seek on regular files; a fixed sliding
  window on non-seekable input.
- **FR-007**: On a file that cannot be opened, MUST write a stderr diagnostic (no header),
  continue with the remaining operands, and exit nonzero.
- **FR-008**: MUST exit 0 when every operand (and stdin) was read successfully.
- **FR-009**: MUST record its README entry (name and binary size) per the constitution.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Output matches the reference `tail` byte-for-byte across the tested cases (default,
  `-n` forms incl. `+N` and `0`, short/empty/no-newline files, multi-file headers, stdin),
  including a fuzz comparison over random contents and counts on both the file and pipe paths.
- **SC-002**: Exit status agrees with the reference for the tested cases.
- **SC-003**: A syscall trace shows only open/read/close/lseek and write (plus exit) - no
  `mmap`/`brk`.
- **SC-004**: Binary meets a < 2 KB target on Linux (1976 B achieved; macOS ~7 KB Mach-O floor).
- **SC-005**: On Linux, at worst as fast as the system `tail`; measured at parity (~1.1×) on a
  38 MB file thanks to the backward seek (no full-file read).

## Assumptions

- Only POSIX option `-n` is implemented (with the `+N` start form). GNU/BSD `-c` (bytes) and
  `-f` (follow) are out of scope in v1 (POSIX-minimal, Principle VIII).
- `-` and `-n 0` follow GNU/POSIX semantics; differential/fuzz stay within the BSD/GNU common
  denominator (they avoid `-`, and treat `-n 0` as empty output which both accept here).
- Diagnostic wording for a failed open differs from the system tool by design; differential
  tests compare stdout and exit code, not stderr text.
- Reuses the file-I/O primitives from `uolt-cat`/`uolt-head` and adds one syscall wrapper,
  `lseek` (per-OS; macOS normalizes the BSD carry-flag error to a negative return).
