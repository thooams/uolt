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

To build and test the **Linux** target locally from macOS, run `sh scripts/linux-test.sh`
(needs a Docker engine such as colima). It uses a prebuilt toolchain image
(`docker/linux-toolchain.Dockerfile`), so after the first run a full build+test cycle takes
a few seconds - faster than pushing to CI.

## Commands

Sizes are shown as **uolt / system tool** so the gain is visible. "System" is the stock
`/usr/bin` tool on each platform (GNU coreutils on Linux, Apple's on macOS).

| Command      | Linux x86_64 (uolt / system) | macOS x86_64 (uolt / system) | Target | Notes                     |
|--------------|------------------------------|------------------------------|--------|---------------------------|
| `uolt-true`  | 360 B / 26936 B (**75× smaller**) | 4560 B / 84128 B (**18× smaller**) | < 1 KB | POSIX `true`; ignores args, no I/O, exits 0. |
| `uolt-false` | 360 B / 26936 B (**75× smaller**) | 4560 B / 84128 B (**18× smaller**) | < 1 KB | POSIX `false`; ignores args, no I/O, exits 1. |

**Size note**: the < 1 KB targets are authoritative on **Linux** and met - a custom link
script (`sys/linux/uolt.ld`) collapses the binary into one segment, giving 360 B (the real
machine code is 21 bytes). **macOS** cannot produce sub-page binaries: every Mach-O executable
carries page-aligned segments plus the `libSystem` load commands, giving an unavoidable floor
around 4 KB. macOS sizes are reported for transparency and measured against the Linux target,
not held to it.
