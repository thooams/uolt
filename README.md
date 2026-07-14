# UOLT — Ultra Optimised Lightweight Toolset

<p align="center">
  <b>31 Unix command-line tools, hand-written in x86_64 assembly.</b><br>
  No libc · no heap · direct syscalls · fully static on Linux.
</p>

<p align="center">
  The <b>entire suite</b> is <b>37 KB</b> on Linux — smaller than a single stock
  <code>grep</code> binary (187 KB), and <b>~57× smaller</b> than the equivalent
  stock tools combined, while staying byte-for-byte compatible.
</p>

---

## What is this?

UOLT reimplements the everyday Unix / POSIX utilities (`cat`, `ls`, `grep`, `sort`, …)
from scratch, entirely in assembly. Each tool is a standalone `uolt-<name>` executable;
shared routines (string length, buffered write, syscall wrappers, …) live in `libuolt`.

The goal is to see how small and lean these tools can get when you strip away every
layer that is not strictly necessary:

- **No C library.** Tools talk to the kernel through raw syscalls; there is no stdio,
  no malloc, no dynamic loader work on Linux.
- **No heap.** Every buffer is on the stack, with documented bounds — allocation never
  fails because it never happens.
- **One toolchain, two targets.** A single clang integrated-assembler build produces
  fully static Linux ELF binaries and macOS Mach-O binaries (which carry only the
  OS-imposed `libSystem` loader stub, with zero calls into it).
- **POSIX behaviour, verified.** Each tool is checked byte-for-byte against the system
  tool (`differential` tests) plus unit / POSIX / fuzz / syscall-trace layers.

See [the constitution](.specify/memory/constitution.md) for the full governing principles.

## Scope: POSIX-first, one library

UOLT is a **single POSIX-first library** — one binary per tool, no second "extended" build and
no runtime mode flag. The rule is simple: **a tool option is implemented if and only if POSIX
specifies it for that tool.** GNU-only options are out of scope. This keeps every tool small and,
as a bonus, differential-testable against the system tool on both Linux (GNU) and macOS (BSD),
since POSIX options are the ones the two implementations agree on.

A closed, grandfathered set of non-POSIX but BSD+GNU-universal extras predates this rule and
stays: `seq` (and its `-s`/`-w`), `grep -w`, and `find -maxdepth`. Nothing further is added to it.

## The whole suite at a glance

<table>
<tr><th>Platform</th><th>UOLT suite (31 tools)</th><th>Stock tools combined</th><th>Smaller by</th></tr>
<tr><td>Linux (static ELF)</td><td><b>36.7 KB</b></td><td>2.08 MB</td><td><b>~57×</b></td></tr>
<tr><td>macOS (Mach-O)</td><td>208 KB</td><td>3.60 MB</td><td>~17×</td></tr>
</table>

Average Linux tool: **~1.1 KB**. The smallest (`true`) is **384 bytes**, of which the
actual machine code is 21 bytes.

## Build

```sh
make            # build every tool into ./build
make test       # run all test layers (unit, POSIX, differential, fuzz, trace)
make bench      # benchmark size + speed vs the reference tools
```

One assembler across platforms: the clang integrated assembler, x86_64 sources in Intel
syntax. To build and test the **Linux** target locally from macOS, run
`sh scripts/linux-test.sh` (needs a Docker engine such as colima). It uses a prebuilt
toolchain image, so after the first run a full build+test cycle takes a few seconds.

## Commands

Sizes are the **Linux** static binary (`uolt`) vs the stock `/usr/bin` tool (GNU
coreutils); the last column is how many times smaller UOLT is. macOS sizes and the full
flag reference are in the collapsible sections below.

### Text output & shell helpers

| Tool | What it does | uolt | system | smaller |
|------|--------------|-----:|-------:|:-------:|
| `true`     | exit 0                                   |  384 B | 26.9 KB | **70×** |
| `false`    | exit 1                                   |  384 B | 26.9 KB | **70×** |
| `echo`     | print arguments (`-n`)                   |  608 B | 35.2 KB | **58×** |
| `pwd`      | physical working directory               |  528 B | 35.3 KB | **67×** |
| `yes`      | repeat a line forever                    |  808 B | 35.2 KB | **44×** |
| `seq`      | integer sequence (`-s`, `-w`)            | 1344 B | 51.7 KB | **38×** |
| `env`      | run a command / print the env (`-i`, `-u`) | 1616 B | 48.1 KB | **30×** |
| `sleep`    | suspend (`s`/`m`/`h`/`d` suffixes)       |  960 B | 35.3 KB | **37×** |
| `basename` | final path component (+ suffix strip)    |  728 B | 35.3 KB | **49×** |
| `dirname`  | directory part of a path                 |  688 B | 35.2 KB | **51×** |

### File contents

| Tool | What it does | uolt | system | smaller |
|------|--------------|-----:|-------:|:-------:|
| `cat`  | concatenate files / stdin (`-u`)                    |  824 B | 39.4 KB | **48×** |
| `head` | first N lines / bytes (`-n`, `-c`)                  | 1472 B | 43.5 KB | **30×** |
| `tail` | last N lines / bytes (`-n`, `-n +N`, `-c`)          | 2312 B | 64.0 KB | **28×** |
| `wc`   | count lines / words / bytes / chars (`-l`/`-w`/`-c`/`-m`) | 1408 B | 55.8 KB | **40×** |
| `tee`  | copy stdin to stdout and files (`-a`)               |  960 B | 39.4 KB | **41×** |

### Text processing

| Tool | What it does | uolt | system | smaller |
|------|--------------|-----:|-------:|:-------:|
| `grep` | fixed-string search (`-i -v -n -c -w -x`, like `grep -F`) | 1912 B | 186.8 KB | **98×** |
| `sort` | sort lines (`-r -n -u -f -b`)                             | 1384 B | 105.3 KB | **76×** |
| `uniq` | collapse adjacent dups (`-c -d -u -i -f -s`)              | 1608 B |  39.4 KB | **25×** |
| `cut`  | select characters / fields (`-c -f -d -s`)               | 1856 B |  39.4 KB | **21×** |
| `tr`   | translate / delete / squeeze / complement bytes (`-d -s -c`) | 1560 B |  47.6 KB | **31×** |
| `comm` | compare two sorted files (`-1 -2 -3`)                    | 1496 B |  39.4 KB | **26×** |

### Filesystem

| Tool | What it does | uolt | system | smaller |
|------|--------------|-----:|-------:|:-------:|
| `ls`    | list entries (`-a`)                                  |  976 B | 142.3 KB | **146×** |
| `find`  | walk a tree (`-type f/d/l`, `-maxdepth`, `-name`)    | 1440 B | 204.3 KB | **142×** |
| `mkdir` | create directories (`-p`, `-m MODE`)                 | 1056 B |  76.3 KB |  **72×** |
| `rmdir` | remove empty directories (`-p`)                      |  848 B |  47.5 KB |  **56×** |
| `touch` | create / update mtime (`-c`)                         |  912 B |  96.8 KB | **106×** |
| `ln`    | hard / symbolic links (`-s`, `-f`, into a dir)       | 1176 B |  55.8 KB |  **47×** |
| `rm`    | remove files and trees (`-r`, `-f`)                  | 1232 B |  59.9 KB |  **49×** |
| `mv`    | rename, or move into a directory                     |  992 B | 137.8 KB | **139×** |
| `cp`    | copy files and trees (`-r`, into a directory)        | 1816 B | 141.8 KB |  **78×** |
| `chmod` | set mode, octal or symbolic (`u+x`, `go-w`, `+X`)    | 1376 B |  55.8 KB |  **41×** |

<details>
<summary><b>macOS sizes (Mach-O)</b></summary>

macOS cannot produce sub-page binaries: every Mach-O executable carries page-aligned
segments plus the `libSystem` load commands, an unavoidable floor around 4 KB. Sizes are
reported for transparency and measured against the Linux target, not held to it.

| Tool | uolt | system | Tool | uolt | system |
|------|-----:|-------:|------|-----:|-------:|
| `true`  | 4664 B |  84.1 KB | `mkdir` | 5728 B | 101.5 KB |
| `false` | 4664 B |  84.1 KB | `rmdir` | 5720 B | 101.1 KB |
| `echo`  | 5160 B | 101.1 KB | `touch` | 6248 B | 101.8 KB |
| `pwd`   | 5504 B | 101.3 KB | `ln`    | 6192 B | 102.2 KB |
| `cat`   | 6048 B | 119.0 KB | `rm`    | 8208 B | 119.2 KB |
| `head`  | 6416 B | 102.0 KB | `mv`    | 5432 B | 119.4 KB |
| `tail`  | 7272 B | 119.3 KB | `cp`    | 6320 B | 153.4 KB |
| `wc`    | 6496 B | 102.2 KB | `chmod` | 5544 B | 120.7 KB |
| `yes`   | 5464 B | 100.9 KB | `ls`    | 7256 B | 154.6 KB |
| `basename` | 5416 B | 101.6 KB | `seq` | 5952 B | 134.8 KB |
| `dirname`  | 5408 B | 101.2 KB | `grep`| 7648 B | 153.8 KB |
| `sleep` | 5704 B | 101.2 KB | `find` | 8928 B | 171.3 KB |
| `tee`   | 9408 B | 101.2 KB | `sort` | 8888 B | 206.0 KB |
| `uniq`  | 9144 B | 102.2 KB | `env`  | 8592 B | 102.4 KB |
| `cut`   | 9840 B | 102.5 KB | `tr`   | 7640 B | 135.3 KB |
| `comm`  | 9136 B | 101.7 KB |        |        |         |

</details>

<details>
<summary><b>Full behaviour &amp; flag notes</b></summary>

**Text output & shell helpers**

- **`true`** — exit 0.
- **`false`** — exit 1.
- **`echo`** — join arguments with spaces and a trailing newline. `-n` suppresses the newline (no `-e` escapes).
- **`pwd`** — print the physical working directory.
- **`yes`** — repeat the operands (or `y`) plus a newline forever, filling a 64 KB buffer to write in large blocks.
- **`seq`** — print an integer sequence: `seq [-s STRING] [-w] [first [incr]] last` (GNU separator semantics).
- **`env`** — run a command with a modified environment: `-i` starts empty, `-u NAME` unsets, `NAME=VALUE` adds or overrides; the command is PATH-searched unless it contains a `/`. With no command, print the environment.
- **`sleep`** — suspend for the sum of the time operands (decimal seconds, optional `s`/`m`/`h`/`d` suffix).
- **`basename`** — print the final component of a path (optional suffix removed); works on the argument bytes only, no file access.
- **`dirname`** — print the directory part of a path; argument bytes only.

**File contents**

- **`cat`** — concatenate operands (or stdin, also for `-`) verbatim in 64 KB blocks. `-u` is accepted and ignored (output is already unbuffered).
- **`head`** — print the first N lines (default 10; `-n` sets N, `-c` counts bytes), with `==> name <==` headers for more than one file.
- **`tail`** — print the last N lines (default 10; `-n` sets N, `-n +N` starts at line N, `-c` counts bytes). Seeks backwards on regular files so cost tracks the output, not the file size; retains the last 64 KB on a pipe.
- **`wc`** — count lines / words / bytes / characters (`-l`/`-w`/`-c`/`-m`; default lines/words/bytes), always in the order lines/words/chars/bytes, with a `total` line for multiple files. In the C locale `-m` equals `-c`.
- **`tee`** — copy stdin to stdout and to each file. `-a` appends.

**Text processing**

- **`grep`** — print input lines containing a fixed-string pattern (like `grep -F`, no regex yet). `-i` case-insensitive, `-v` invert, `-n` line numbers, `-c` count, `-w` word match, `-x` whole line.
- **`sort`** — sort lines in C-locale byte order (input held in a 1 MB buffer). `-r` reverse, `-n` numeric, `-u` unique, `-f` fold case, `-b` ignore leading blanks.
- **`uniq`** — collapse adjacent duplicate lines. `-c` count, `-d` duplicated only, `-u` unique only, `-i` case-insensitive, `-f N` skip fields, `-s N` skip chars.
- **`cut`** — select character positions (`-c`) or delimiter fields (`-f`/`-d`) with ranges. `-s` drops lines with no delimiter.
- **`tr`** — translate, delete (`-d`), or squeeze repeats (`-s`) bytes; `-c` complements set1 so the operation applies to every byte not listed. Sets support `a-z` ranges.
- **`comm`** — compare two sorted files in three columns. `-1`/`-2`/`-3` suppress columns.

**Filesystem**

- **`ls`** — list directory entries one per line. `-a` includes hidden entries. Output is not sorted; columns / `-l` are not yet supported.
- **`find`** — list paths recursively. `-type f`/`d`/`l` filter, `-maxdepth N`, `-name` glob with `*`/`?`.
- **`mkdir`** — create directories. `-p` makes parents and is idempotent; `-m MODE` sets the exact octal mode.
- **`rmdir`** — remove empty directories. `-p` removes the ancestor chain.
- **`touch`** — create missing files and update timestamps to now. `-c` skips creation.
- **`ln`** — create hard links, or symbolic with `-s`; `-f` replaces an existing target; links one or more sources into a directory when the final operand is one.
- **`rm`** — remove files, and with `-r` directory trees. `-f` ignores missing operands.
- **`mv`** — rename a source to a target, or move one or more sources into a directory (final operand being an existing directory).
- **`cp`** — copy a file to a target, with `-r` a directory tree, or one or more sources into an existing directory (mode preservation not yet supported).
- **`chmod`** — set permission bits from an octal or symbolic mode (`u+x`, `go-w`, `a=r`, `+X`, umask-aware).

All tools ignore unrelated arguments.

</details>

## Performance

Timings are measured with `hyperfine` (mean of thousands of runs). The constitution
requires each tool to be **at worst as fast as the system tool, at best faster**.

| Where UOLT is faster | Why |
|----------------------|-----|
| `true` `false` `echo` `pwd` `basename` `dirname` (**~1.4–2.0×**) | pure startup, no I/O — the tiny static binary and minimal syscalls dominate |
| `wc` (**~11×**) | counts bytes in the C locale; stock `wc` does multibyte/locale word processing by default (counts match `wc` under `LC_ALL=C`) |

Every other tool sits at **parity within noise**, and that is expected: `cat`, `sort`,
`grep`, `cp`, … are **I/O-bound**. Their throughput is set by `read`/`write` and memory
bandwidth, which the kernel handles identically no matter who calls it; the byte-scanning
CPU work is comparable, and on realistic inputs process/syscall time dominates. UOLT wins
clearly only where the workload is *startup*, not *data*. Claiming a throughput advantage
elsewhere would be dishonest — parity satisfies the "at worst as fast" floor. On **macOS**
the ~3 ms of exec/dyld work per spawn swamps the tool's own microseconds, so everything
sits at parity there. Run `make bench` to reproduce.

## Size

The `< 1–2 KB` targets are authoritative on **Linux** and met: a custom link script
(`sys/linux/uolt.ld`) collapses each binary into a single segment. macOS sizes are
reported for transparency (see the collapsible section above) and measured against the
Linux target, not held to it.

## License

MIT — see [LICENSE](LICENSE).

These utilities are original, clean-room implementations written from the POSIX
specifications; they are **not** derived from GNU coreutils (which is GPLv3) or any other
existing source, so no copyleft obligation applies. The permissive MIT license lets anyone
reuse the code freely.
