// sys/linux/getdents.S - Linux x86_64 directory-read primitive.
//
// sys_getdents(fd in rdi, buf in rsi, count in rdx) -> bytes: fill buf with
// linux_dirent64 records (getdents64 syscall 217); returns the number of bytes
// written (0 at end of directory) or a negative errno. Owns the syscall number
// (Principle V). Each record: d_ino(8) d_off(8) d_reclen(u16 at 16) d_type(1)
// d_name(from 19) - see DIRENT_* in uolt.inc.

#include "uolt.inc"

.set SYS_GETDENTS64, 217

.text
.globl sys_getdents
sys_getdents:
    mov     rax, SYS_GETDENTS64
    syscall
    ret
