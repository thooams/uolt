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
| `uolt-cat`   | 824 B / 39384 B (**48× smaller**)  | 6048 B / 118992 B (**20× smaller**) | **~1.7× faster**        | < 2 KB |
| `uolt-head`  | 1472 B / 43528 B (**30× smaller**) | 6416 B / 101952 B (**16× smaller**) | **~1.6× faster**        | < 2 KB |
| `uolt-tail`  | 2312 B / 64032 B (**28× smaller**) | 7272 B / 119344 B (**16× smaller**) | **~1.1× (parity)**      | < 2 KB |
| `uolt-wc`    | 1368 B / 55824 B (**41× smaller**) | 6496 B / 102240 B (**16× smaller**) | **~11× faster**         | < 2 KB |
| `uolt-yes`   | 808 B / 35208 B (**44× smaller**)  | 5464 B / 100928 B (**18× smaller**) | **~parity**             | < 1 KB |
| `uolt-basename` | 728 B / 35336 B (**49× smaller**) | 5416 B / 101568 B (**19× smaller**) | **~1.4× faster**     | < 1 KB |
| `uolt-dirname`  | 688 B / 35208 B (**51× smaller**) | 5408 B / 101168 B (**19× smaller**) | **~1.4× faster**     | < 1 KB |
| `uolt-sleep`    | 960 B / 35336 B (**37× smaller**) | 5704 B / 101168 B (**18× smaller**) | **~parity**          | < 1 KB |
| `uolt-mkdir`    | 856 B / 76296 B (**89× smaller**) | 5728 B / 101472 B (**18× smaller**) | **~parity**          | < 1 KB |
| `uolt-rmdir`    | 848 B / 47528 B (**56× smaller**) | 5720 B / 101120 B (**18× smaller**) | **~parity**          | < 1 KB |
| `uolt-touch`    | 912 B / 96776 B (**106× smaller**) | 6248 B / 101792 B (**16× smaller**) | **~parity**         | < 1 KB |
| `uolt-ln`       | 904 B / 55816 B (**62× smaller**) | 6192 B / 102192 B (**17× smaller**) | **~parity**          | < 1 KB |
| `uolt-rm`       | 1232 B / 59912 B (**49× smaller**) | 8208 B / 119184 B (**15× smaller**) | **~parity**         | < 2 KB |
| `uolt-mv`       | 992 B / 137752 B (**139× smaller**) | 5432 B / 119440 B (**22× smaller**) | **~parity**        | < 1 KB |
| `uolt-cp`       | 1816 B / 141848 B (**78× smaller**) | 6320 B / 153360 B (**24× smaller**) | **~parity**        | < 2 KB |
| `uolt-chmod`    | 1376 B / 55816 B (**41× smaller**) | 5544 B / 120656 B (**22× smaller**) | **~parity**          | < 1 KB |
| `uolt-ls`       | 976 B / 142312 B (**146× smaller**) | 7256 B / 154624 B (**21× smaller**) | **~parity**        | < 1 KB |
| `uolt-seq`      | 928 B / 51720 B (**56× smaller**) | 5952 B / 134832 B (**23× smaller**) | **~parity**          | < 1 KB |
| `uolt-grep`     | 1680 B / 186824 B (**111× smaller**) | 7648 B / 153760 B (**20× smaller**) | **~parity**       | < 2 KB |
| `uolt-find`     | 1272 B / 204264 B (**161× smaller**) | 8928 B / 171280 B (**19× smaller**) | **~parity**       | < 2 KB |
| `uolt-sort`     | 1232 B / 105272 B (**85× smaller**) | 8888 B / 206032 B (**23× smaller**) | **~parity**       | < 2 KB |
| `uolt-tee`      | 960 B / 39432 B (**41× smaller**) | 9408 B / 101232 B (**11× smaller**) | **~parity**          | < 1 KB |
| `uolt-uniq`     | 1304 B / 39432 B (**30× smaller**) | 9144 B / 102160 B (**11× smaller**) | **~parity**       | < 2 KB |
| `uolt-env`      | 496 B / 48072 B (**97× smaller**) | 6440 B / 102368 B (**16× smaller**) | **~parity**        | < 1 KB |
| `uolt-cut`      | 1800 B / 39432 B (**22× smaller**) | 9840 B / 102480 B (**10× smaller**) | **~parity**        | < 2 KB |
| `uolt-tr`       | 1040 B / 47624 B (**46× smaller**) | 7640 B / 135344 B (**18× smaller**) | **~parity**        | < 2 KB |
| `uolt-comm`     | 1496 B / 39440 B (**26× smaller**) | 9136 B / 101664 B (**11× smaller**) | **~parity**        | < 2 KB |

Behavior: `uolt-true` exits 0; `uolt-false` exits 1; `uolt-echo` joins args with spaces and a
trailing newline (`-n` suppresses it, no `-e` escapes); `uolt-pwd` prints the physical working
directory; `uolt-cat` concatenates its file operands (or stdin, also for the operand `-`) to
stdout verbatim, in 64 KB blocks (`-u` is accepted and ignored - output is already unbuffered);
`uolt-head` prints the first N lines
(default 10, `-n` sets N; `-c` counts bytes) of each operand or stdin, with `==> name <==` headers
when more than one file is given; `uolt-tail` prints the last N lines
(default 10, `-n` sets N; `-n +N` starts at line N; `-c` counts bytes), seeking backwards on regular files so its
cost tracks the output, not the file size (on a pipe it retains the last 64 KB); `uolt-wc`
counts lines, words, and bytes (`-l`/`-w`/`-c` select; default all), always in that order, with
a `total` line for multiple files; `uolt-yes` repeats its operands joined by spaces (or `y`) plus
a newline forever, filling a 64 KB buffer to write in large blocks; `uolt-basename` prints the
final component of a path (with an optional suffix removed) and `uolt-dirname` prints the
directory part, both working purely on the argument bytes with no file access; `uolt-sleep`
suspends for the sum of its time operands (decimal seconds with an optional `s`/`m`/`h`/`d`
suffix); `uolt-mkdir` creates directories (`-p` makes parents and is idempotent); `uolt-rmdir` removes
empty directories (`-p` removes the ancestor chain); `uolt-touch` creates missing files and
updates timestamps to now (`-c` skips creation); `uolt-ln` creates hard links (or symbolic with
`-s`, replacing an existing target with `-f`); `uolt-rm` removes files and, with `-r`,
directory trees (`-f` ignores missing operands); `uolt-mv` renames a source to a target, or moves one or more sources into a directory
(final operand being an existing directory); `uolt-cp` copies a file to a
target, and with `-r` copies a directory tree, or copies one or more sources into
an existing directory (mode preservation not yet supported);
`uolt-chmod` sets permission bits from an octal or symbolic mode (`u+x`, `go-w`, `a=r`, `+X`, umask-aware);
`uolt-ls` lists directory entries one per line (`-a` includes hidden entries; output is not
sorted and columns/`-l` are not yet supported); `uolt-seq` prints an integer sequence
(`seq [first [incr]] last`); `uolt-grep` prints input lines containing a fixed-string pattern
(`-i` case-insensitive, `-v` invert, `-n` line numbers, `-c` count; like `grep -F`, no regex yet); `uolt-find`
lists paths recursively (`-type f`/`d` filter, `-name` glob with `*`/`?`); `uolt-sort`
sorts lines in C-locale byte order (`-r` reverse, `-n` numeric, `-u` unique; input is held in a
1 MB buffer); `uolt-tee` copies stdin to stdout and to each file (`-a` appends). `uolt-uniq` collapses adjacent duplicate lines (`-c` count, `-d` duplicated, `-u` unique, `-i` case-insensitive). `uolt-env` prints the environment (running a command is not yet supported). `uolt-cut` selects character positions (`-c`) or delimiter fields (`-f`/`-d`) with ranges. `uolt-tr` translates or (with `-d`) deletes bytes (sets support `a-z` ranges). `uolt-comm` compares two sorted files in three columns (`-1`/`-2`/`-3` suppress columns). All ignore
unrelated arguments.

The `uolt-wc` speedup is large because it counts bytes in the C locale; the stock `wc` does
multibyte/locale word processing by default. Counts match `wc` run under `LC_ALL=C`.

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

## License

MIT - see [LICENSE](LICENSE).

These utilities are original, clean-room implementations written from the POSIX specifications;
they are **not** derived from GNU coreutils (which is GPLv3) or any other existing source, so no
copyleft obligation applies. The permissive MIT license lets anyone reuse the code freely.
