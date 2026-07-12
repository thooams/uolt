# CLI Contract: uolt-true

The observable contract of the `uolt-true` executable. Tests assert exactly this.

## Invocation

```
uolt-true [any arguments...]
```

## Inputs

| Input        | Contract                                                        |
|--------------|----------------------------------------------------------------|
| Arguments    | All arguments are accepted and ignored. Any count, any value.  |
| Standard in  | Never read. May be closed, a terminal, a pipe, or a file.      |
| Environment  | Ignored. No variable affects behavior.                         |
| Files / cwd  | Not touched. Behavior is independent of the file system.       |

## Outputs

| Output        | Contract                          |
|---------------|-----------------------------------|
| Standard out  | Nothing. 0 bytes, always.         |
| Standard err  | Nothing. 0 bytes, always.         |
| Exit status   | `0` (success), always.            |

## Behavior

- Deterministic: identical result on every invocation (FR-006).
- Matches the POSIX `true` utility (FR-007).
- No options are recognized in v1 (no `--help`, no `--version`); such strings are treated as
  ordinary ignored arguments.

## Verification matrix

| Test layer    | Assertion                                                              |
|---------------|-----------------------------------------------------------------------|
| unit          | `uolt-true; test $? -eq 0` and captured stdout/stderr are empty        |
| posix         | `uolt-true a b --c`, streams redirected/closed → exit 0, no output     |
| differential  | exit code and output byte-identical to reference `true` for each case  |
| fuzz          | random argv + random stream states → never exit != 0, never any output |
| trace         | syscall trace contains only the `exit` call; no read/write/mmap/brk    |
| bench         | size < 1 KB, startup < 1 ms, compared to GNU/BSD/BusyBox/Toybox        |
