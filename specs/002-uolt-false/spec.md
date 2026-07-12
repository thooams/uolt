# Feature Specification: uolt-false

**Feature Branch**: `002-uolt-false` (built on `main`)  
**Created**: 2026-07-12  
**Status**: Implemented  
**Input**: User description: "uolt-false"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Signal failure in a script (Priority: P1)

A user writing or running a shell script needs a command that does nothing and always
reports failure. They invoke `uolt-false`; it produces no output and returns a non-zero exit
status, letting the surrounding script or control-flow construct take its failure path.

**Why this priority**: This is the entire purpose of the tool and the mirror of `uolt-true`.

**Independent Test**: Run `uolt-false` and inspect the exit status (`echo $?` → `1`) and
confirm no bytes are written to stdout or stderr.

**Acceptance Scenarios**:

1. **Given** a shell prompt, **When** the user runs `uolt-false`, **Then** it exits with a
   non-zero status (`1`).
2. **Given** a shell prompt, **When** the user runs `uolt-false`, **Then** nothing is written
   to stdout or stderr.

---

### Edge Cases

- **Arguments provided**: any arguments (e.g. `uolt-false foo --bar`) are ignored; still
  exits `1`.
- **Streams closed/redirected**: stdin/stdout/stderr closed or to `/dev/null` → still exit
  `1`, no output (no I/O performed).
- **Repeated use**: every invocation exits `1` independently.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The command MUST always terminate with a non-zero exit status (`1`).
- **FR-002**: The command MUST NOT write any bytes to stdout.
- **FR-003**: The command MUST NOT write any bytes to stderr.
- **FR-004**: The command MUST ignore all command-line arguments and still exit `1`.
- **FR-005**: The command MUST NOT read from stdin.
- **FR-006**: Behavior MUST be identical on every invocation, independent of environment,
  arguments, or stream state.
- **FR-007**: The command MUST match the behavior expected of the POSIX `false` utility.
- **FR-008**: The command MUST record its README entry (name and binary size at minimum) per
  the constitution before being considered complete.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of invocations exit with status `1`, including runs with arguments and
  redirected/closed streams.
- **SC-002**: 0 bytes are ever written to stdout or stderr.
- **SC-003**: Behavior matches the reference POSIX `false` in a differential test.
- **SC-004**: The delivered binary meets the < 1 KB target on Linux (macOS has a ~4 KB Mach-O
  floor; see constitution and README).
- **SC-005**: Startup-to-exit completes in under 1 millisecond.

## Assumptions

- Mirror of `uolt-true`; reuses the same scaffolding (`libuolt`, `sys/`, Makefile, harness).
- Non-zero status is `1`, matching POSIX `false` and the shell convention.
- No options (`--help`/`--version`) in v1; such strings are ordinary ignored arguments.
