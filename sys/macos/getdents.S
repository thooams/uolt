// sys/macos/getdents.S - macOS x86_64 directory-read primitive.
//
// macOS has no getdents; it uses getdirentries64 (syscall 344), which takes a
// fourth argument, a pointer to an off_t position that it reads and updates.
// This wrapper hides that difference: sys_getdents(fd in rdi, buf in rsi, count
// in rdx) -> bytes, keeping the position on the stack so the caller's ABI matches
// Linux. Returns bytes written (0 at end) or a negative errno.
//
// Each record is the macOS 64-bit dirent: d_ino(8) d_seekoff(8) d_reclen(u16 at
// 16) d_namlen(2) d_type(1) d_name(from 21) - see DIRENT_* in uolt.inc.

#include "uolt.inc"

.set SYS_GETDIRENTRIES64, 0x2000158        // 0x2000000 | 344

.text
.globl sys_getdents
sys_getdents:
    sub     rsp, 16                 // off_t position scratch (the fd's own offset
    mov     qword ptr [rsp], 0      // drives paging, like read; basep is an output)
    mov     r10, rsp                // 4th arg: &position
    mov     rax, SYS_GETDIRENTRIES64
    syscall
    add     rsp, 16
    jc      1f
    ret
1:
    neg     rax
    ret
