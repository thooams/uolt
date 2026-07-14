# Feature Specification: uolt-find

**Feature Branch**: `024-uolt-find` (built on `main`)  
**Created**: 2026-07-13  
**Status**: Implemented (walk + -type)  
**Input**: User description: "find"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - List a tree (Priority: P1)

`uolt-find path` prints `path` and every path beneath it, one per line; with no operand it walks
".".

**Acceptance Scenarios**:

1. **Given** a directory tree, **When** `find dir`, **Then** every path in it prints.
2. **Given** no operand, **When** `find`, **Then** it walks the current directory.
3. **Given** a file operand, **When** `find file`, **Then** just that path prints.

---

### User Story 2 - Filter by type (Priority: P2)

`-type f` restricts output to regular files, `-type d` to directories. Symlinks are classified as
links (not files), matching `find` without -L.

**Acceptance Scenarios**:

1. **Given** `-type f`, **When** run, **Then** only regular files print (symlinks excluded).
2. **Given** `-type d`, **When** run, **Then** only directories print.

---

### Edge Cases

- Traversal order is filesystem-defined (not sorted); comparisons are done as sorted sets.
- Symlinks are not followed and are typed as links (via the directory entry's d_type).
- A directory that cannot be opened (e.g. permission) is skipped.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: MUST print each start path and, recursively, every path under it, one per line;
  default start is ".".
- **FR-002**: `-type f`/`d` MUST restrict output to regular files / directories; symlinks are
  typed as links.
- **FR-003**: MUST not follow symlinks (types come from the directory entry, not from stat).
- **FR-004**: MUST use no heap (Principle IV): a per-level directory buffer and a single shared
  path buffer.
- **FR-005**: MUST record its README entry (name and binary size) per the constitution.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The set of paths matches the system `find` (sorted) for the walk and -type f|d
  cases, including a symlink (excluded from -type f).
- **SC-002**: Binary meets a < 2 KB target on Linux (1072 B achieved; macOS ~8.9 KB floor).

## Assumptions

- `-name` (glob) and the other predicates/actions (-maxdepth, -exec, -print0, ...) are out of
  scope in v1. Only the recursive listing and `-type f|d` are supported; `-type` is recognized as
  the trailing two operands.
- Reuses the `opendir`/`getdents` primitives (from `ls`) plus `close`/`write`/`strlen`. Entry
  types come from d_type (DIRENT_TYPE_OFF in uolt.inc); DT_UNKNOWN falls back to opening the path.
