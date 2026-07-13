# Feature Specification: uolt-sleep

**Feature Branch**: `012-uolt-sleep` (built on `main`)  
**Created**: 2026-07-13  
**Status**: Implemented  
**Input**: User description: "sleep"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Wait for a duration (Priority: P1)

A script needs to pause. `uolt-sleep 2` waits two seconds, then exits 0.

**Independent Test**: `uolt-sleep 0.3` returns after ~0.3 s with exit 0.

**Acceptance Scenarios**:

1. **Given** an integer, **When** `uolt-sleep 1`, **Then** it waits ~1 s and exits 0.
2. **Given** a fraction, **When** `uolt-sleep 0.3`, **Then** it waits ~0.3 s.
3. **Given** several operands, **When** `uolt-sleep 0.1 0.1`, **Then** it waits ~0.2 s (summed).

---

### User Story 2 - Unit suffixes (Priority: P2)

`uolt-sleep 2m` waits two minutes; suffixes are s (seconds, default), m, h, d.

**Acceptance Scenarios**:

1. **Given** `0.25s`, **When** run, **Then** it waits ~0.25 s.
2. **Given** an invalid operand, **When** run, **Then** it prints a diagnostic and exits 1.

---

### Edge Cases

- No operand is an error (exit 1).
- A signal interrupting the sleep is handled: it resumes for the remaining time (Linux), or
  retries (macOS).
- macOS has no direct `nanosleep` syscall, so the sleep is implemented with `select`.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: MUST suspend execution for the sum of the time operands, then exit 0.
- **FR-002**: Each operand is a non-negative decimal with an optional fractional part and an
  optional single unit suffix s/m/h/d (default seconds).
- **FR-003**: MUST error (stderr + exit 1) on an invalid operand or when none is given.
- **FR-004**: MUST resume/retry across a signal interruption.
- **FR-005**: MUST use no heap (Principle IV); the time struct is on the stack.
- **FR-006**: MUST record its README entry (name and binary size) per the constitution.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The elapsed time is within a generous band of the requested duration across the
  tested cases (integer, fraction, sum, suffix).
- **SC-002**: Exit status is 0 on success and nonzero on an invalid/missing operand.
- **SC-003**: A syscall trace shows the sleep primitive (nanosleep on Linux) and no `mmap`/`brk`.
- **SC-004**: Binary meets a < 1 KB target on Linux (960 B achieved; macOS ~5.7 KB Mach-O floor).
- **SC-005**: Timing is dominated by the sleep itself, so throughput is at parity by construction.

## Assumptions

- Fractional seconds, unit suffixes, and multiple summed operands are the GNU form; the
  no-suffix integer case is the POSIX requirement. BSD sleep takes a single operand, so no
  differential timing test is attempted (timing is not byte-comparable anyway).
- macOS lacks a direct `nanosleep` syscall (libc uses `__semwait_signal`), so the per-OS sleep
  primitive uses `select` there and `nanosleep` on Linux, behind one `uolt_sleep(sec, nsec)`.
- Adds the per-OS `sleep` primitive; reuses `write`/`strlen` for diagnostics.
