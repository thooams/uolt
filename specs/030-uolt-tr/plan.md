# Implementation Plan: uolt-tr

**Branch**: `main` (spec dir `030-uolt-tr`) | **Date**: 2026-07-14

Translate or delete bytes. `expand_set` turns a set string (with a-z ranges) into a byte list; a
256-entry map (identity, then map[set1[i]] = set2[min(i,len2-1)]) and a 256-entry delete table
are built on the stack. The transform reads 64 KB blocks and emits map[b] (or drops deleted b).
No new syscall.

## Constitution Check
All PASS: assembly; read/write direct; static/stub; no heap (2x64 KB buffer + 512 B tables on
stack); uolt_* wrappers; 1040 B; measured; documented; unit+differential.

## Structure
- src/tr/tr.S: option scan (-d/--), expand_set, build map/delete tables, block transform
- tests/{unit,differential}/tr.sh
