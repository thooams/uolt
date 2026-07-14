# Feature Specification: uolt-env

**Feature Branch**: `028-uolt-env` | **Date**: 2026-07-14 | **Status**: Implemented (print only)

## Summary

`env`: print each environment variable ("NAME=value") on its own line. Running a command with a
modified environment (env [NAME=value...] command) needs execve and is out of scope in v1;
operands are ignored and the environment is printed.

## Requirements
- FR-001: MUST print every environment entry, one per line, terminated by a newline.
- FR-002: MUST use no heap (Principle IV); entries are read from the process's own env block.
- FR-003: README entry recorded.

## Success Criteria
- SC-001: The environment printed matches the system env (sorted, excluding the shell-set "_").
- SC-002: Binary < 1 KB on Linux (496 B; macOS ~6.4 KB floor).

## Assumptions
- Command execution and -i/-u/-0 are out of scope in v1. The environment array is found at
  argv + (argc + 1) * 8 (envp follows argv's NULL terminator on both Linux and macOS), so no
  entry-shim change is needed. Reuses write/strlen only.
