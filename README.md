# UOLT - Ultra Optimised Lightweight Toolset

A handcrafted suite of Unix utilities written entirely in assembly, designed for minimal
size, predictable performance, and zero unnecessary abstraction. Shared logic lives in
`libuolt`; each utility ships as a `uolt-<name>` executable.

See [the constitution](.specify/memory/constitution.md) for the governing principles
(assembly-only, direct syscalls, no heap, POSIX-not-GNU, tested & benchmarked).

## Build

```sh
make            # build every tool into ./build
make test       # run all test layers (unit, POSIX, differential, fuzz, trace)
make bench      # benchmark vs reference tools
```

One assembler across platforms: the clang integrated assembler, x86_64 sources in Intel
syntax. Linux binaries are fully static; macOS binaries carry only the OS-imposed
`libSystem.dylib` loader stub (zero calls into it, direct syscalls only).

## Commands

| Command      | Size (macOS x86_64) | Size target | Notes                                             |
|--------------|---------------------|-------------|---------------------------------------------------|
| `uolt-true`  | 4560 B              | < 1 KB      | POSIX `true`; ignores args, no I/O, exits 0. See note on size. |
| `uolt-false` | 4560 B              | < 1 KB      | POSIX `false`; ignores args, no I/O, exits 1. See note on size. |

**Size note**: the < 1 KB targets are authoritative on **Linux** (tiny static ELF; the real
`uolt-true` machine code is 21 bytes). **macOS** cannot produce sub-page binaries: every
Mach-O executable carries page-aligned segments plus the `libSystem` load commands, giving an
unavoidable floor around 4 KB. macOS sizes are reported for transparency and measured against
the Linux target, not held to it.
