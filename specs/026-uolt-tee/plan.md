# Implementation Plan: uolt-tee

**Branch**: `main` (spec dir `026-uolt-tee`) | **Date**: 2026-07-14

Copy stdin to stdout and every file, `-a` to append. Adds the per-OS `openapp` primitive
(O_WRONLY|O_CREAT|O_APPEND; flags differ by OS); reuses opendst/read/write/close/strlen.

## Constitution Check
All principles PASS: pure assembly; direct syscalls; static/stub; no heap (64 KB stack buffer +
fd array); `uolt_*` wrappers; 960 B; measured; POSIX subset (`-a`); documented; tested.

## Structure
- sys/{linux,macos}/openapp.S (0x441 / 0x209); libuolt/openapp.S
- src/tee/tee.S: option scan (-a/--), open each file, read/drain to stdout + each fd, close
- tests/{unit,differential}/tee.sh
