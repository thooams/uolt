# Feature Specification: uolt-echo

**Feature Branch**: `003-uolt-echo` (built on `main`)  
**Created**: 2026-07-12  
**Status**: Implemented  
**Input**: User description: "echo"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Print text to stdout (Priority: P1)

A user or script needs to write a line of text. They run `uolt-echo hello world`; it prints
`hello world` followed by a newline. This is the first UOLT tool that performs real output
and reads its arguments.

**Independent Test**: `uolt-echo a b c` writes exactly `a b c\n` to stdout and exits 0.

**Acceptance Scenarios**:

1. **Given** a shell, **When** `uolt-echo hello`, **Then** stdout is `hello\n` and exit is 0.
2. **Given** several arguments, **When** `uolt-echo a b c`, **Then** they are joined by single
   spaces and terminated by one newline.
3. **Given** no arguments, **When** `uolt-echo`, **Then** stdout is a single newline.

---

### User Story 2 - Suppress the trailing newline with -n (Priority: P2)

A user needs output without a trailing newline (e.g. building a prompt). `uolt-echo -n foo`
prints `foo` with no newline.

**Independent Test**: `uolt-echo -n foo` writes `foo` (3 bytes, no newline) and exits 0.

**Acceptance Scenarios**:

1. **Given** `-n` as the first argument, **When** `uolt-echo -n foo`, **Then** stdout is `foo`
   with no trailing newline.
2. **Given** only `-n`, **When** `uolt-echo -n`, **Then** stdout is empty.

---

### Edge Cases

- Arguments containing backslashes are printed literally (no escape processing; no `-e`).
- Very long or many arguments are printed correctly.
- `-n` is only recognized as the first argument; later `-n` is printed literally.
- Output stream closed/redirected does not change argument handling.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: MUST write each argument to stdout, separated by a single space (0x20).
- **FR-002**: MUST terminate output with a single newline (0x0A) unless `-n` is given.
- **FR-003**: MUST treat a leading `-n` as an option that suppresses the trailing newline and
  is not itself printed.
- **FR-004**: MUST NOT process backslash escape sequences (POSIX, not GNU `-e`).
- **FR-005**: With no arguments, MUST print a single newline (or nothing if `-n`).
- **FR-006**: MUST exit `0`.
- **FR-007**: MUST perform no heap allocation and read nothing from stdin.
- **FR-008**: MUST record its README entry (name and binary size) per the constitution.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Output matches the reference `/bin/echo` byte-for-byte across the tested cases
  (plain args, `-n`, empty, many args), including a fuzz comparison over random argv.
- **SC-002**: 100% of invocations exit `0`.
- **SC-003**: A syscall trace shows only `write` (and `exit`) - no `read`, `mmap`, or `brk`.
- **SC-004**: Binary meets a < 3 KB target on Linux (608 B achieved; macOS ~5 KB Mach-O
  floor, per the size note in README).
- **SC-005**: Startup-to-exit under 1 ms.

## Assumptions

- `-n` support with no `-e` escapes is the common POSIX/BSD denominator that both GNU and BSD
  `echo` agree on for the tested inputs.
- Output uses one `write` syscall per piece (arg / space / newline); a single-`writev`
  coalescing is a deferred, measured optimization (constitution Principle VII).
- Reuses all scaffolding; adds `libuolt` `strlen`/`write` and the per-OS `write` wrapper, plus
  a per-OS entry shim (`sys/<os>/start.S`) introduced with this tool.
