# Feature Specification: uolt-yes

**Feature Branch**: `009-uolt-yes` (built on `main`)  
**Created**: 2026-07-13  
**Status**: Implemented  
**Input**: User description: "yes"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Repeat a line forever (Priority: P1)

A user needs an endless stream of a line to feed a prompt or a pipeline. They run `uolt-yes`; it
writes `y` on every line until the reader goes away.

**Independent Test**: `uolt-yes | head -3` prints three `y` lines.

**Acceptance Scenarios**:

1. **Given** no operands, **When** `uolt-yes`, **Then** every line is `y` followed by a newline.
2. **Given** a downstream reader that closes (e.g. `head`), **When** the pipe breaks, **Then**
   the tool stops (SIGPIPE) rather than spinning.

---

### User Story 2 - Repeat given operands (Priority: P2)

`uolt-yes hello world` repeats `hello world` on every line: the operands joined by single spaces.

**Independent Test**: `uolt-yes a b c | head -1` prints `a b c`.

**Acceptance Scenarios**:

1. **Given** one operand, **When** run, **Then** each line is that operand.
2. **Given** several operands, **When** run, **Then** each line is the operands joined by single
   spaces (GNU behavior).

---

### Edge Cases

- Output is byte-identical on every line; the buffer replication introduces no seams.
- A single line longer than 64 KB falls back to emitting it piecewise from argv each iteration.
- The tool only ever exits via a signal (SIGPIPE) or a write error (status 1); there is no
  normal termination.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: MUST repeatedly write a line to stdout: the operands joined by single spaces, or
  `y` when there are none, always terminated by a newline.
- **FR-002**: MUST sustain high throughput by writing in large blocks (a 64 KB buffer filled with
  whole copies of the line), not one line per syscall.
- **FR-003**: MUST use no heap (Principle IV): the buffer is on the stack.
- **FR-004**: MUST stop when the write fails (SIGPIPE by default, or exit 1 on -EPIPE).
- **FR-005**: MUST handle a line longer than the buffer by emitting it piecewise.
- **FR-006**: MUST record its README entry (name and binary size) per the constitution.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Output matches the reference `yes` byte-for-byte for the no-operand and
  single-operand cases (the multi-operand case differs between GNU and BSD; see Assumptions).
- **SC-002**: A syscall trace shows only `write` (and exit) - no `mmap`, `brk`, `read`, or `open`.
- **SC-003**: Binary meets a < 1 KB target on Linux (808 B achieved; macOS ~5.5 KB Mach-O floor).
- **SC-004**: On Linux, throughput is at parity with the system `yes` (both are pipe-bound; the
  measurement is noise-dominated in the CI VM).

## Assumptions

- `yes` is not a POSIX utility. This tool follows the GNU semantics: all operands are joined by
  single spaces. BSD `yes` uses only the first operand, so differential tests compare only the
  no-operand and single-operand cases where GNU and BSD agree.
- Exit is never "normal": the process runs until a signal or write error. Status 1 is returned
  only if SIGPIPE is ignored and the write returns an error.
- Reuses `write`/`strlen`; adds no new syscall. Buffer replication uses `rep movsb`.
