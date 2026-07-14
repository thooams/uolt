---
description: "Task list for uolt-grep implementation"
---

# Tasks: uolt-grep

**Prerequisites**: open/read/close/write/strlen (from cat).

**Tests**: INCLUDED (Principle XI).

## Phase 1: Tool

- [x] T001 [US1] `src/grep/grep.S`: option scan (-i/-v, combined, --); pattern operand; per-file
        `grep_fd` line loop over a 64 KB buffer (newline split, compaction, buffer-full flush,
        final no-newline line)
- [x] T002 [US1] `contains`: naive substring search (base pointer per start index to stay within
        two-register addressing); optional ASCII case fold
- [x] T003 [US2] `process_line`: apply -v, record any match, print with an optional "file:" prefix;
        exit status 0/1/2
- [x] T004 Makefile: `EXTRA_grep` + append `grep` to `TOOLNAMES`

## Phase 2: Tests

- [x] T005 [P] `tests/unit/grep.sh`: basic/-i/-v, stdin, multi-file prefix, no-newline line,
        exit-status convention
- [x] T006 [P] `tests/differential/grep.sh`: match `grep -F` output + exit across the cases

## Phase 3: Polish

- [x] T007 Wire grep tests into `make test`
- [x] T008 Update `README.md` with the `uolt-grep` row
- [x] T009 Verify macOS + Linux: all pass. Linux 1448 B (< 2 KB)

## Notes

- Assembler constraint: `[base + index + index]` (three registers) is invalid; the inner compare
  precomputes `&line[i]` into a base register so the loop uses two-register addressing.
- Fixed-string only (like grep -F). Regex and -n/-c/-l/-r/-w/-x deferred.
