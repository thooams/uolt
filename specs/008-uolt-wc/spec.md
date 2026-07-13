# Feature Specification: uolt-wc

**Feature Branch**: `008-uolt-wc` (built on `main`)  
**Created**: 2026-07-13  
**Status**: Implemented  
**Input**: User description: "wc"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Count a file (Priority: P1)

A user wants to know how big a file is. They run `uolt-wc file`; it prints the line, word, and
byte counts followed by the name, and exits 0.

**Independent Test**: `uolt-wc FILE` prints three counts and the name; exit 0.

**Acceptance Scenarios**:

1. **Given** a text file, **When** `uolt-wc file`, **Then** stdout is `<lines> <words> <bytes>
   file` and exit is 0.
2. **Given** an empty file, **When** `uolt-wc file`, **Then** the counts are all zero.
3. **Given** a final line without a trailing newline, **When** counted, **Then** it adds a word
   (and bytes) but not a line.

---

### User Story 2 - Select counts with -l/-w/-c (Priority: P1)

A user wants only some counts. `uolt-wc -l file` prints just the line count; flags combine
(`-lw`) and may be given separately (`-l -w`). Whatever the flag order, the output order is
always lines, words, bytes.

**Independent Test**: `uolt-wc -c -l file` prints the line count then the byte count.

**Acceptance Scenarios**:

1. **Given** `-l`, **When** run, **Then** only the line count (and name) is printed.
2. **Given** `-c -l`, **When** run, **Then** output is `<lines> <bytes> name` (fixed order).
3. **Given** no count flag, **When** run, **Then** all three counts print.

---

### User Story 3 - Standard input and multiple files (Priority: P2)

With no operand `uolt-wc` counts standard input (no name). Given several files it prints a line
per file and a final `total` line summing the columns.

**Independent Test**: `printf 'a b c\n' | uolt-wc` prints `1 3 6`.

**Acceptance Scenarios**:

1. **Given** piped input and no operand, **When** run, **Then** the stream's counts print with
   no name.
2. **Given** two files, **When** `uolt-wc a b`, **Then** each file's counts print, followed by a
   `total` line.
3. **Given** an unreadable operand among others, **When** run, **Then** it yields a stderr
   diagnostic, the others are still counted, and the exit status is nonzero.

---

### Edge Cases

- A "word" is a maximal run of non-<blank> bytes; <blank> is the C-locale set: space, tab (0x09),
  newline (0x0a), vertical tab (0x0b), form feed (0x0c), carriage return (0x0d).
- Counting is byte-based (C locale); this both matches `wc` under `LC_ALL=C` and is much faster
  than the stock tool's default multibyte processing.
- Bytes are counted exactly, including NUL and high bytes (binary-safe).
- Column spacing is implementation-defined; this tool uses a single space, no padding.
- `-m` (characters) and the stdin alias `-` are out of scope in v1.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: MUST count lines (newlines), words (non-blank runs), and bytes of each operand.
- **FR-002**: `-l`, `-w`, `-c` select which counts print; they combine and may repeat; with none
  given, all three print.
- **FR-003**: Counts MUST print in the order lines, words, bytes regardless of flag order.
- **FR-004**: With no operand MUST count standard input and print no name.
- **FR-005**: With more than one operand MUST print a final `total` line summing the columns.
- **FR-006**: MUST use no heap (Principle IV): input flows through one 64 KB stack buffer; counts
  live in registers / stack locals.
- **FR-007**: On a file that cannot be opened, MUST write a stderr diagnostic, continue, and
  exit nonzero.
- **FR-008**: MUST exit 0 when every operand (and stdin) was counted successfully.
- **FR-009**: MUST record its README entry (name and binary size) per the constitution.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Counts match the reference `wc` (run under `LC_ALL=C`) across the tested cases
  (default, each flag, combined, empty, no-newline, tabs, multi-file totals, stdin), including a
  fuzz comparison over random text.
- **SC-002**: Exit status agrees with the reference for the tested cases.
- **SC-003**: A syscall trace shows only open/read/close and write (plus exit) - no `mmap`/`brk`.
- **SC-004**: Binary meets a < 2 KB target on Linux (1368 B achieved; macOS ~6.5 KB Mach-O floor).
- **SC-005**: On Linux, at worst as fast as the system `wc`; measured ~11× faster on a ~50 MB
  file (byte-based counting vs the stock tool's default multibyte pass).

## Assumptions

- Byte-based, C-locale counting is the intended semantics (POSIX-minimal, Principle VIII); `-m`
  and multibyte word rules are deferred.
- Column spacing is implementation-defined, so differential tests normalize whitespace and
  compare the counts, not the padding; the reference runs under `LC_ALL=C`.
- Diagnostic wording for a failed open differs from the system tool by design.
- Reuses the file-I/O primitives from `uolt-cat` (open/read/close) plus write/strlen; adds no new
  syscall. Includes a small integer-to-decimal formatter (`put_uint`).
