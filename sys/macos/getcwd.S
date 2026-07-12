// sys/macos/getcwd.S - macOS x86_64 current-working-directory query.
//
// macOS blocks the direct __getcwd syscall (326): calling it raises SIGSYS and
// the kernel kills the process (verified). So this wrapper reproduces the same
// result with syscalls macOS *does* allow directly: open the current directory
// and ask the descriptor for its path via fcntl(F_GETPATH), then close it.
//
// This is exactly why the cwd query lives behind a per-OS wrapper (Principle V):
// the tool calls one sys_getcwd; only this file knows the platform dance.
//
// sys_getcwd(buf in rdi, size in rsi) -> 0 on success (buf holds the NUL-
// terminated path), -1 on error. `size` is unused here (F_GETPATH expects a
// buffer of at least MAXPATHLEN, which callers provide).

#include "uolt.inc"

.set SYS_OPEN,   0x2000005      // open
.set SYS_CLOSE,  0x2000006      // close
.set SYS_FCNTL,  0x200005c      // fcntl (92)
.set F_GETPATH,  50             // fcntl cmd: fetch the path of a descriptor
.set O_RDONLY,   0

.text
.globl sys_getcwd
sys_getcwd:
    mov     r8, rdi             // save caller's buffer (r8/r9 survive syscalls)

    lea     rdi, [rip + dot]    // open(".", O_RDONLY)
    mov     rsi, O_RDONLY
    mov     rax, SYS_OPEN
    syscall
    jc      .err
    mov     r9, rax             // fd

    mov     rdi, r9             // fcntl(fd, F_GETPATH, buf)
    mov     rsi, F_GETPATH
    mov     rdx, r8
    mov     rax, SYS_FCNTL
    syscall
    jc      .err_close

    mov     rdi, r9             // close(fd)
    mov     rax, SYS_CLOSE
    syscall
    xor     rax, rax            // success
    ret

.err_close:
    mov     rdi, r9             // close the fd even on fcntl failure
    mov     rax, SYS_CLOSE
    syscall
.err:
    mov     rax, -1
    ret

dot: .asciz "."
