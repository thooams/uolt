# Contract: Cross-Arch Internal API & Syscall Wrapper

This is the interface that MUST hold identical across `x86_64` and `arm64` so tool bodies stay
arch-selectable without changing which symbols they call (Principle V, FR-006/FR-007). "Signature"
here is the register-level calling contract, expressed abstractly (arg0, arg1, … = the platform's
1st, 2nd, … argument register: `rdi,rsi,rdx,…` on x86_64; `x0,x1,x2,…` on aarch64; return in the
platform's return register `rax`/`x0`).

## Entry contract

- `_start` (per OS-and-arch): kernel entry → `uolt_main(arg0=argc, arg1=argv)` → `uolt_exit(arg0=status)`.
- `uolt_main`: defined by each tool body; returns status in the return register.

## Internal API symbols (libuolt) — signatures fixed across arch

| Symbol | Args (abstract) | Returns | Notes |
|--------|-----------------|---------|-------|
| `uolt_exit` | arg0 = status | does not return | tail-calls `sys_exit` |
| `uolt_write` | arg0=fd, arg1=buf, arg2=len | bytes written / -errno | tail-calls `sys_write` |
| `uolt_read` | arg0=fd, arg1=buf, arg2=len | bytes read / -errno | |
| `uolt_strlen` | arg0=ptr | length | NUL-terminated |
| `uolt_open` | arg0=path, arg1=flags, arg2=mode | fd / -errno | wrapper hides openat/AT_FDCWD |
| `uolt_close` | arg0=fd | 0 / -errno | |
| `uolt_getcwd` | arg0=buf, arg1=size | len / -errno | |
| `uolt_lseek` | arg0=fd, arg1=off, arg2=whence | pos / -errno | |
| `uolt_mmap_anon` | arg0=size | addr / -errno (in -4095..-1) | zero-filled RW private anon |
| `uolt_munmap` | arg0=addr, arg1=size | 0 / -errno | |
| `uolt_opendir` / `uolt_getdents` | dir path / (fd,buf,len) | fd / bytes | getdents64 both arches |
| `uolt_mkdir` | arg0=path, arg1=mode | 0 / -errno | hides mkdirat/AT_FDCWD |
| `uolt_rmdir` | arg0=path | 0 / -errno | hides unlinkat+AT_REMOVEDIR |
| `uolt_unlink` | arg0=path | 0 / -errno | hides unlinkat |
| `uolt_rename` | arg0=old, arg1=new | 0 / -errno | hides renameat |
| `uolt_link` / `uolt_symlink` | arg0=target, arg1=linkpath | 0 / -errno | hides linkat/symlinkat |
| `uolt_chmod` | arg0=path, arg1=mode | 0 / -errno | hides fchmodat |
| `uolt_access` | arg0=path, arg1=mode | 0 / -errno | hides faccessat |
| `uolt_statmode` / `uolt_lstatmode` | arg0=path | st_mode / -errno | hides newfstatat + arch stat offset |
| `uolt_statsize` | arg0=path | st_size / -errno | hides newfstatat + arch stat offset |
| `uolt_utimes` | arg0=path, arg1=times | 0 / -errno | hides utimensat + timeval→timespec |
| `uolt_execve` | arg0=path, arg1=argv, arg2=envp | -errno on fail | |
| `uolt_sleep` | arg0=timespec | 0 / -errno | nanosleep |

Contract rule: adding an arch MUST NOT change any row above. If aarch64 forces a signature change,
that is a contract break and MUST be resolved inside the wrapper, not pushed up to callers.

## Syscall wrapper contract (sys/linux/<arch>/)

- Each wrapper owns exactly one raw syscall number (Principle V) and performs the trap
  (`syscall` / `svc #0`).
- For the `*at` family on aarch64, the wrapper injects `AT_FDCWD` and the correct flags so the
  symbolic entry (`sys_open`, `sys_unlink`, `sys_rmdir`, `sys_stat`, `sys_lstat`, …) presents the
  SAME argument list the x86_64 wrapper presents. See research.md D2 for the full mapping.
- `struct stat` field offsets consumed by `sys_stat`/`sys_lstat` results are arch-specific
  (research.md D3) and defined in arch scope, never in the shared header.

## Behavioral (CLI) contract

Unchanged. Each tool's user-facing behavior is its existing POSIX contract, already fixed by its
own `specs/00N-uolt-<tool>/` and enforced by the shared differential corpus. This port adds no new
user-facing option and removes none; the aarch64 body MUST satisfy the exact same corpus as x86_64.
