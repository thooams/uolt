# Feature Specification: uolt-ls

**Feature Branch**: `021-uolt-ls` (built on `main`)  
**Created**: 2026-07-13  
**Status**: Implemented (one-per-line, unsorted)  
**Input**: User description: "ls"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - List a directory (Priority: P1)

`uolt-ls` lists the entries of the current directory, one per line; `uolt-ls dir` lists `dir`.

**Acceptance Scenarios**:

1. **Given** a directory of files, **When** `ls`, **Then** each entry prints on its own line.
2. **Given** a directory operand, **When** `ls dir`, **Then** its entries print.
3. **Given** an empty directory, **When** run, **Then** nothing prints, exit 0.

---

### User Story 2 - Hidden entries with -a (Priority: P2)

`uolt-ls -a` includes entries whose name starts with '.', including "." and "..".

---

### User Story 3 - File operands (Priority: P2)

`uolt-ls file` prints the file's name (the operand as given); a missing operand is a diagnostic.

---

### Edge Cases

- Output is not sorted (v1): sorting an unbounded name set has no bounded, heap-free form.
- `-1` is accepted and is the default; column output and `-l` are out of scope in v1.
- A directory is detected by opening with O_DIRECTORY (ENOTDIR marks a file).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: MUST list each directory operand's entries, one name per line; no operand lists ".".
- **FR-002**: Without -a MUST omit entries whose name begins with '.'; with -a MUST include them.
- **FR-003**: A file operand MUST print its name; a missing operand MUST diagnose and set exit 1.
- **FR-004**: MUST use no heap (Principle IV): entries flow through a fixed 32 KB stack buffer.
- **FR-005**: MUST record its README entry (name and binary size) per the constitution.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: For a single operand, the set of names matches the system `ls -1` (compared sorted,
  since order is undefined) across the tested cases (cwd, -a, named dir, empty, file, many).
- **SC-002**: A syscall trace shows the directory-read syscall (getdents64 on Linux) and no
  `mmap`/`brk`.
- **SC-003**: Binary meets a < 1 KB target on Linux (976 B achieved; macOS ~7.3 KB floor).

## Assumptions

- Sorting, column layout, `-l`, and per-operand headers for multiple operands are out of scope in
  v1. Output is one name per line, in directory order.
- Adds the per-OS directory-read primitive: `getdents` (Linux getdents64 217, macOS
  getdirentries64 344 - which takes a position pointer, hidden in the wrapper) and `opendir`
  (open O_RDONLY|O_DIRECTORY - the flag value differs by OS). The dirent field offsets live in
  `uolt.inc`, selected by a build-time -DUOLT_OS_* define. macOS getdirentries64 works as a direct
  syscall (unlike getcwd/nanosleep, which are gated).
