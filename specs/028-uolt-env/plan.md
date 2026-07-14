# Implementation Plan: uolt-env

**Branch**: `main` (spec dir `028-uolt-env`) | **Date**: 2026-07-14

Print the environment. envp = argv + (argc+1)*8 (envp follows argv's NULL on both OSes), so the
tool walks it and writes each string + newline. Reuses write/strlen; no new syscall.

## Constitution Check
All PASS: pure assembly; only write; static/stub; no heap; uolt_* wrappers; 496 B; trivial;
print-only subset; documented; unit+differential.

## Structure
- src/env/env.S: compute envp from argc/argv, loop printing entries
- tests/{unit,differential}/env.sh
