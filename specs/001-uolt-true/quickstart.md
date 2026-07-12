# Quickstart: uolt-true

## Prerequisites

- `nasm` (assembler)
- `ld` / system linker (part of binutils on Linux, Xup command-line tools on macOS)
- `make`
- For tests: a POSIX shell, a reference `true` (coreutils / BSD / BusyBox / Toybox),
  `strace` (Linux) or `dtruss` (macOS)

## Build

```sh
make               # builds all tools, including uolt-true, into ./build
make build/uolt-true   # build just this tool
```

The build detects the host OS and assembles the matching `sys/<os>/` wrappers. Output is a
static, dependency-free binary at `build/uolt-true`.

## Run

```sh
./build/uolt-true            # exits 0, prints nothing
echo $?                      # -> 0
./build/uolt-true a b --c    # arguments ignored, still exits 0
```

## Test

```sh
make test                    # runs unit, posix, differential, fuzz, and trace layers
tests/unit/true.sh           # run a single layer
```

Expected: every layer passes; the trace layer shows only the `exit` syscall.

## Benchmark

```sh
make bench                   # compares time / memory / size vs GNU, BSD, BusyBox, Toybox
```

## Verify the constitution targets

```sh
size -A build/uolt-true      # or: wc -c build/uolt-true   -> under 1 KB
ldd build/uolt-true          # Linux: "not a dynamic executable" (fully static)
```

## README

After building, record `uolt-true` in the project `README.md` command table with its name and
measured binary size (constitution Principle X). The command is not "done" until that entry
exists and is accurate.
