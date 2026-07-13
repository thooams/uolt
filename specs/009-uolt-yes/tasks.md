---
description: "Task list for uolt-yes implementation"
---

# Tasks: uolt-yes

**Prerequisites**: write + strlen (from echo).

**Tests**: INCLUDED (Principle XI).

## Phase 1: Research

- [x] T001 Confirm throughput matters (naive one-line-per-write is slow) and settle the operand
        semantics: GNU joins all operands, BSD uses only the first; follow GNU and note the
        divergence for the differential test

## Phase 2: Tool

- [x] T002 [US1] `src/yes/yes.S`: build the line ("y" or operands joined by spaces + newline);
        compute L; guard L > 64 KB
- [x] T003 [US1] Replicate the line to fill a 64 KB buffer (doubling `rep movsb`); infinite
        write loop draining short writes; exit 1 on write error
- [x] T004 [US2] Piecewise fallback for a line longer than the buffer (emit argv + separators
        each iteration)
- [x] T005 Makefile: `EXTRA_yes` (strlen + write) + append `yes` to `TOOLNAMES`

## Phase 3: Tests

- [x] T006 [P] `tests/unit/yes.sh`: default "y", single/multiple operands (joined), trailing
        newline, large sample consistency
- [x] T007 [P] `tests/posix/yes.sh`: default line, spacing/join, sample uniformity, long-line
        fallback
- [x] T008 [P] `tests/differential/yes.sh`: match reference `yes` on no-operand and
        single-operand samples (multi-operand diverges GNU vs BSD)
- [x] T009 [P] `tests/trace/yes.sh`: only write; no mmap/brk/read/open (stopped via SIGPIPE)

## Phase 4: Polish

- [x] T010 Wire yes tests into `make test`; add yes size row to `bench/run.sh`
- [x] T011 Update `README.md` with the `uolt-yes` row
- [x] T012 Verify macOS + Linux: all pass. Linux 808 B (< 1 KB), throughput at parity with the
        system yes (pipe-bound, noise-dominated in the VM); trace shows only write

## Notes

- Trace test pipes uolt-yes into `head`; head closing the pipe stops it via SIGPIPE. Care was
  needed not to redirect stdout to /dev/null (that would detach the sink and let it spin).
- No fuzz layer: the output is a fixed infinite stream with nothing to randomize.
