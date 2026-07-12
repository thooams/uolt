# Feature Specification: uolt-true

**Feature Branch**: `001-uolt-true`  
**Created**: 2026-07-12  
**Status**: Draft  
**Input**: User description: "uolt-true"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Signal success in a script (Priority: P1)

A user writing or running a shell script needs a command that does nothing and always
reports success. They invoke `uolt-true`; it produces no output and returns a success exit
status, letting the surrounding script or control-flow construct proceed as if a step
succeeded.

**Why this priority**: This is the entire purpose of the tool. Without it, there is nothing
to deliver. It is also the smallest, simplest tool in UOLT and validates the full build,
link, and syscall-abstraction chain end to end.

**Independent Test**: Run `uolt-true` in a shell and inspect the exit status (`echo $?` →
`0`) and confirm no bytes are written to stdout or stderr. Fully testable on its own.

**Acceptance Scenarios**:

1. **Given** a shell prompt, **When** the user runs `uolt-true`, **Then** the command exits
   with status `0`.
2. **Given** a shell prompt, **When** the user runs `uolt-true`, **Then** nothing is written
   to standard output.
3. **Given** a shell prompt, **When** the user runs `uolt-true`, **Then** nothing is written
   to standard error.

---

### User Story 2 - Reliable loop and conditional primitive (Priority: P2)

A user uses the command as a control-flow primitive, for example as the condition of a loop
(`while uolt-true; do ...; done`) or the success branch of a conditional. The command must
behave identically on every invocation so the surrounding logic is predictable.

**Why this priority**: A stable, always-success primitive is a common scripting building
block. It depends on Story 1 being correct and adds the expectation of repeatability.

**Independent Test**: Invoke `uolt-true` many times in a row (and inside a loop condition)
and confirm every invocation exits `0` with no output.

**Acceptance Scenarios**:

1. **Given** a loop `while uolt-true; do break; done`, **When** it runs, **Then** the loop
   body executes and the loop condition never fails.
2. **Given** repeated invocations, **When** `uolt-true` is run 1000 times, **Then** every
   invocation exits `0`.

---

### Edge Cases

- **Arguments provided**: When invoked with any arguments (e.g. `uolt-true foo --bar`), the
  command ignores them and still exits `0`, matching POSIX behavior.
- **Standard streams closed or redirected**: When stdin, stdout, or stderr are closed,
  redirected to `/dev/null`, or connected to a closed pipe, the command still exits `0`
  because it performs no I/O.
- **Environment**: The command's result does not depend on environment variables, current
  directory, or file system state.
- **Repeated / concurrent use**: Many simultaneous or back-to-back invocations each exit `0`
  independently.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The command MUST always terminate with an exit status of `0` (success).
- **FR-002**: The command MUST NOT write any bytes to standard output.
- **FR-003**: The command MUST NOT write any bytes to standard error.
- **FR-004**: The command MUST ignore all command-line arguments and still exit `0`.
- **FR-005**: The command MUST NOT read from standard input.
- **FR-006**: The command's behavior MUST be identical on every invocation, independent of
  environment, arguments, or stream state.
- **FR-007**: The command MUST match the behavior expected of the POSIX `true` utility.
- **FR-008**: The command MUST record its README entry (name and binary size at minimum) per
  the project constitution before being considered complete.

### Key Entities

Not applicable - the command processes no data and manages no entities.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of invocations exit with status `0`, across at least 1000 test runs,
  including runs with arguments and with redirected/closed streams.
- **SC-002**: 0 bytes are ever written to standard output or standard error across all test
  runs.
- **SC-003**: Behavior matches the reference POSIX `true` utility in a differential test
  (same exit status, same absence of output) for every tested invocation.
- **SC-004**: The delivered binary meets the constitution size target of under 1 KB.
- **SC-005**: Command startup-to-exit completes in under 1 millisecond, per the constitution
  startup target.

## Assumptions

- The tool follows the UOLT constitution: POSIX behavior (not GNU), no options such as
  `--help` or `--version` are required for the initial version.
- Standard success exit status is `0`, matching POSIX and the shell convention.
- Any arguments are silently ignored, consistent with POSIX `true`.
- The tool performs no I/O, so stream and file-system state cannot affect its result.
- Constitution constraints (assembly-only, static, no heap, no dependencies, size and startup
  targets) apply and are validated during implementation and testing.
