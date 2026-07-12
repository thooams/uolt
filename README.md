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

| Command      | Size Linux (uolt / system)        | Size macOS (uolt / system)          | Speed Linux (vs system) | Target |
|--------------|-----------------------------------|-------------------------------------|-------------------------|--------|
| `uolt-true`  | 384 B / 26936 B (**70× smaller**)  | 4664 B / 84128 B (**18× smaller**)  | **~1.8× faster**        | < 1 KB |
| `uolt-false` | 384 B / 26936 B (**70× smaller**)  | 4664 B / 84128 B (**18× smaller**)  | **~1.8× faster**        | < 1 KB |
| `uolt-echo`  | 608 B / 35208 B (**58× smaller**)  | 5160 B / 101136 B (**20× smaller**) | **~2.0× faster**        | < 3 KB |
| `uolt-pwd`   | 528 B / 35336 B (**67× smaller**)  | 5504 B / 101296 B (**18× smaller**) | **~1.9× faster**        | < 2 KB |

Behavior: `uolt-true` exits 0; `uolt-false` exits 1; `uolt-echo` joins args with spaces and a
trailing newline (`-n` suppresses it, no `-e` escapes); `uolt-pwd` prints the physical working
directory. All ignore unrelated arguments.

**Speed note**: timings are measured with `hyperfine` (mean of thousands of runs). The
constitution requires each tool to be **at worst as fast as the system tool, at best faster**.
On **Linux** the static, tiny binaries win clearly (no dynamic linker to load): ~1.8-2.0×
faster. On **macOS** process-spawn overhead (~3 ms of exec/dyld work) dominates and swamps the
tool's own microseconds, so results sit at **parity within noise** - the rule accepts parity
where the OS overhead is fixed and outside our control. Run `make bench` to reproduce.

**Size note**: the < 1 KB targets are authoritative on **Linux** and met - a custom link
script (`sys/linux/uolt.ld`) collapses the binary into one segment, giving 360 B (the real
machine code is 21 bytes). **macOS** cannot produce sub-page binaries: every Mach-O executable
carries page-aligned segments plus the `libSystem` load commands, giving an unavoidable floor
around 4 KB. macOS sizes are reported for transparency and measured against the Linux target,
not held to it.
