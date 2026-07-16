# Rewriting 34 Unix tools in assembly: what I learned

*A draft announcement / write-up for UOLT. Publish it on a blog (dev.to,
Hashnode, your own site), then submit the link to Hacker News and the relevant
subreddits. The one hook that carries everything: **the whole suite is smaller
than a single `grep` binary.***

---

I rewrote 34 of the everyday Unix / POSIX tools — `cat`, `ls`, `sort`, `grep`,
`wc`, `printf`, `test`, `expr`, and friends — from scratch in x86_64 assembly.
No libc, no heap, direct syscalls. The entire suite is **~44 KB** on Linux:
smaller than one stock `grep` (187 KB), and ~49× smaller than the equivalent
coreutils combined. The smallest tool, `true`, is 384 bytes — 21 of which are
actual machine code.

It is not a toy pile. Every tool is checked **byte-for-byte** against the system
tool (differential tests), plus unit / POSIX / fuzz / syscall-trace layers, on
both Linux (GNU) and macOS (BSD). You can shadow your coreutils on `PATH`
reversibly, and `sort` / `tail` / `uniq` handle unbounded input, so it is a
genuine drop-in for POSIX use rather than a demo.

Here is what the assembly-and-no-libc constraint actually forced me to learn.

## macOS gates specific syscalls with SIGSYS

On x86_64 macOS, calling the `__getcwd` syscall directly raises `SIGSYS` and the
kernel kills the process. `getpid`, `write`, and `exit` work fine, so the
mechanism is intact — Apple just gates *specific* syscalls. `nanosleep` is worse:
it is not a direct syscall at all on macOS (libc implements it via
`__semwait_signal`), and the raw number returns immediately.

So the syscall abstraction has to absorb per-OS reality, not just per-OS numbers:

- `pwd` uses `getcwd(2)` on Linux, but `open(".")` + `fcntl(F_GETPATH)` +
  `close` on macOS.
- `sleep` uses `nanosleep` on Linux and a `select()` with a timeout on macOS.

The lesson: test every new syscall on macOS early, behind a thin per-OS wrapper,
because the surprises are individual, not systematic.

## "No heap" is a design constraint, not a slogan

Forbidding `malloc` changes how tools are shaped:

- `tail` finds the last N lines of a regular file by `lseek`-ing to the end and
  scanning fixed blocks *backwards* — cost tracks the output, not the file size.
- `wc` does a single byte scan in the C locale, which turned out ~11× faster than
  stock `wc`'s default multibyte pass on a 50 MB file.

But some tools genuinely need all the input at once. `sort` is the honest case.
The first version used a fixed 1 MB stack buffer and an insertion sort — which
means it silently truncated anything larger and was O(n²) on top. That is not an
alternative to anything.

The fix that keeps the spirit of "no hidden heap": an **explicit, failure-checked
`mmap`** region that grows on demand (map larger, copy, `munmap` the old one),
plus a stable bottom-up merge sort and a buffered writer. It is tool-owned, it
reports out-of-memory instead of corrupting output, and it is nothing like a
libc heap. Output buffering alone took a 1M-line sort from ~2.6s (dominated by
one `write` syscall per line) to parity with GNU `sort`.

## The toolchain fights you in tiny, specific ways

Three bugs that each cost a debug cycle:

- **ld64 dead-strips `jmp`-only helpers.** On macOS Mach-O, a helper defined as
  its own non-dot symbol and reached only via `jmp` got silently removed by the
  linker (`subsections_via_symbols`), and the caller's label was aliased onto the
  next function. The fix is to inline such tail helpers with dot-local labels — or
  reach them with `call`, which keeps them alive.
- **`FLAGS` is a reserved name** in clang's integrated assembler. `.set FLAGS, …`
  fails with "invalid operand". Name your constant anything else.
- **GAS turns `mov rX, location_diff` into a memory load.** In Intel-noprefix
  syntax, `mov rdx, SYM` where `SYM` is a `. - str` location difference assembles
  as a *load from address 0xa*, not an immediate — instant segfault. Measure
  string lengths with `strlen`, or verify with `objdump` that the operand has a
  `$`.

## One toolchain, two OSes

Everything builds with clang's integrated assembler, x86_64 in Intel syntax. The
Linux target is fully static (a custom link script collapses everything into one
segment, then `strip`); macOS carries only the OS-imposed `libSystem` loader stub,
with zero calls into it. Same sources, `make`, done.

## Where it goes next

It is x86_64 only for now — arm64 is the obvious next frontier (and macOS blocks
direct syscalls there, so that will be its own adventure). A regex engine would
unlock `grep`'s patterns and `expr`'s `:` operator. The no-heap rule will keep
being the interesting constraint.

Repo, tests, and the full size table: **https://github.com/thooams/uolt**
(MIT). Install via `nix`, a Homebrew tap, the AUR, or `make`.

I would love to hear where the no-libc / no-heap approach breaks down next.
