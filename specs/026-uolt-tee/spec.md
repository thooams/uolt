# Feature Specification: uolt-tee

**Feature Branch**: `026-uolt-tee` | **Date**: 2026-07-14 | **Status**: Implemented

## Summary

`tee [-a] [file...]`: copy standard input to standard output and to each named file, `-a`
appending instead of truncating. Data flows through one 64 KB stack buffer (no heap); each read
block is drained to stdout and every open file. Up to 64 files; an unopenable file diagnoses and
sets exit 1 without stopping the others.

## Requirements

- **FR-001**: MUST copy stdin to stdout and to each file operand.
- **FR-002**: `-a` MUST append; otherwise files are created/truncated.
- **FR-003**: An unopenable file MUST diagnose and set exit 1 but not stop the copy to the rest.
- **FR-004**: MUST use no heap (Principle IV); short writes are drained.
- **FR-005**: MUST record its README entry per the constitution.

## Success Criteria

- **SC-001**: stdout and file contents match the system `tee` for the fan-out and `-a` cases,
  including binary/multi-block input.
- **SC-002**: Binary < 1 KB on Linux (960 B; macOS ~9.4 KB floor).

## Assumptions

- Up to 64 output files; `-` is treated as a file operand. Adds the per-OS `openapp`
  (O_WRONLY|O_CREAT|O_APPEND) primitive; reuses opendst/read/write/close/strlen.
