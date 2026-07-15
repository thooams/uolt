// src/printf/printf.S - uolt-printf: the POSIX `printf` utility.
//
// printf format [argument...]: write the arguments under the control of the
// format string, exactly like the C printf family and the POSIX `printf`
// utility. The format is reused (cycled) as long as unconsumed arguments remain
// and the previous pass consumed at least one argument.
//
// Supported in the format string:
//   - backslash escapes  \\ \a \b \f \n \r \t \v \" and \ddd (1-3 octal digits)
//   - conversions        %d %i %u %o %x %X %c %s %b %%
//   - flags              -  +  (space)  #  0
//   - field width and precision as decimal numbers
//
// Deliberately deferred (documented limitation, revisited when needed, same
// spirit as `seq` deferring floats): the floating conversions %e %E %f %g %G
// %a %A, and the dynamic `*` width/precision. Field width and precision are
// each capped at WIDTHMAX (they build into a bounded stack buffer - Principle IV,
// no heap). A %b result is likewise capped at BSIZE bytes.
//
// Numeric arguments are parsed like C integer constants (optional sign, then
// 0x.. hex / 0.. octal / decimal); a leading ' or " takes the numeric value of
// the following byte (POSIX). A missing argument is the empty string for %s/%c
// and zero for the numeric conversions.
//
// Called as uolt_main(argc in rdi, argv in rsi) by the per-OS entry shim.
//
// All output funnels through one 4 KB stack buffer (OBUF) so ordering is exact
// and syscalls are batched; it is flushed once at the end (and before an error
// or a %b "\c" stop). Helper routines keep their live state in stack locals so
// the callee-saved registers holding the format walk survive every call.

#include "uolt.inc"

.set STDOUT, 1
.set STDERR, 2

// Conversion-spec flag bits (LOC_FLAGS).
.set FLAG_MINUS, 1          // '-' left-justify
.set FLAG_PLUS,  2          // '+' always sign
.set FLAG_SPACE, 4          // ' ' space before a non-negative number
.set FLAG_HASH,  8          // '#' alternate form (0 / 0x prefix)
.set FLAG_ZERO,  16         // '0' zero-pad to width

.set WIDTHMAX, 256          // cap on width and precision (bounds NUM buffer)
.set OBSIZE,   4096         // output buffer size
.set BSIZE,    4096         // %b expansion buffer size

// Stack locals (qword unless noted). One rbp frame; see FRAME below. Offsets
// start below -40 because the prologue's five pushed callee-saved registers
// (rbx, r12-r15) occupy [rbp-8 .. rbp-40].
.set LOC_ARGP,     -56      // &argv[2]: base of the argument vector
.set LOC_ARGC,     -64      // number of arguments (argc - 2)
.set LOC_ARGI,     -72      // index of the next argument to consume
.set LOC_WIDTH,    -80      // parsed field width
.set LOC_PREC,     -88      // parsed precision (-1 = none)
.set LOC_PPTR,     -96      // ob_put: source pointer
.set LOC_PLEN,     -104     // ob_put: remaining length
.set LOC_PADN2,    -112     // emit_pad: remaining count
.set LOC_SPTR,     -120     // emit_str: string pointer
.set LOC_SLEN,     -128     // emit_str: string length
.set LOC_ESPAD,    -136     // emit_str: pad count
.set LOC_CNPAD,    -144     // conv_num: pad count (survives ob_put clobber)
.set LOC_FLAGS,    -152     // byte: conversion flags
.set LOC_UPPER,    -160     // byte: uppercase hex digits
.set LOC_UNSIGNED, -168     // byte: unsigned conversion (no sign logic)
.set LOC_NEG,      -176     // byte: value is negative (signed conversions)
.set LOC_NONZERO,  -184     // byte: value is non-zero (for '#' hex prefix)
.set LOC_BASE,     -192     // byte: numeric base (8/10/16)
.set LOC_PADCH,    -200     // byte: emit_pad fill character
.set PFXOFF,       -208     // 4-byte sign/hex-prefix scratch
.set NUMEND,       -216     // number buffer: build downward from here
// NUM buffer occupies [NUMEND-320, NUMEND); then the two big buffers below it.
.set BBUFOFF,      -4632    // %b expansion buffer (BSIZE bytes)
.set OBOFF,        -8728    // output buffer (OBSIZE bytes)
.set OBLEN,        -8736    // current OBUF fill (kept just below the buffer)
.set FRAME,        9216     // total frame (covers every offset above)

.text
.globl uolt_main
uolt_main:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, FRAME
    cld

    // rdi = argc, rsi = argv. Need at least argv[0] and a format operand.
    cmp     rdi, 2
    jl      .missing_format

    lea     rax, [rsi + 16]                 // &argv[2]
    mov     [rbp + LOC_ARGP], rax
    lea     rax, [rdi - 2]                  // argument count
    mov     [rbp + LOC_ARGC], rax
    mov     r13, [rsi + 8]                  // format = argv[1] (callee-saved)
    mov     qword ptr [rbp + LOC_ARGI], 0
    mov     qword ptr [rbp + OBLEN], 0

.cycle:
    mov     r14, [rbp + LOC_ARGI]           // consumed-before mark for this pass
    mov     r12, r13                        // format walk pointer

.fmt_loop:
    movzx   eax, byte ptr [r12]
    test    al, al
    jz      .fmt_end
    cmp     al, 0x5c                        // '\'
    je      .esc
    cmp     al, '%'
    je      .conv
    call    ob_putc                         // ordinary byte (al)
    inc     r12
    jmp     .fmt_loop

.esc:
    inc     r12                             // past '\'
    call    do_escape
    jmp     .fmt_loop

.conv:
    inc     r12                             // past '%'
    cmp     byte ptr [r12], '%'
    jne     .conv_spec
    inc     r12
    mov     al, '%'
    call    ob_putc
    jmp     .fmt_loop

.fmt_end:
    // Re-cycle while arguments remain and this pass made progress.
    mov     rax, [rbp + LOC_ARGI]
    cmp     rax, [rbp + LOC_ARGC]
    jae     .finish
    cmp     rax, r14
    jbe     .finish
    jmp     .cycle

.finish:
    call    ob_flush
    xor     eax, eax
    jmp     .ret

.missing_format:
    lea     rdi, [rip + err_usage]
    call    err_puts
    mov     eax, 1
    jmp     .ret

.bad_spec:
    call    ob_flush
    lea     rdi, [rip + err_spec]
    call    err_puts
    mov     eax, 1

.ret:
    add     rsp, FRAME
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

// -------- conversion specification: flags, width, precision, conversion -------
.conv_spec:
    mov     byte ptr [rbp + LOC_FLAGS], 0
    mov     qword ptr [rbp + LOC_WIDTH], 0
    mov     qword ptr [rbp + LOC_PREC], -1
    mov     byte ptr [rbp + LOC_UPPER], 0
    mov     byte ptr [rbp + LOC_UNSIGNED], 0
    mov     byte ptr [rbp + LOC_NEG], 0

.cs_flags:
    movzx   eax, byte ptr [r12]
    cmp     al, '-'
    je      .fl_minus
    cmp     al, '+'
    je      .fl_plus
    cmp     al, ' '
    je      .fl_space
    cmp     al, '#'
    je      .fl_hash
    cmp     al, '0'
    je      .fl_zero
    jmp     .cs_width
.fl_minus:
    or      byte ptr [rbp + LOC_FLAGS], FLAG_MINUS
    inc     r12
    jmp     .cs_flags
.fl_plus:
    or      byte ptr [rbp + LOC_FLAGS], FLAG_PLUS
    inc     r12
    jmp     .cs_flags
.fl_space:
    or      byte ptr [rbp + LOC_FLAGS], FLAG_SPACE
    inc     r12
    jmp     .cs_flags
.fl_hash:
    or      byte ptr [rbp + LOC_FLAGS], FLAG_HASH
    inc     r12
    jmp     .cs_flags
.fl_zero:
    or      byte ptr [rbp + LOC_FLAGS], FLAG_ZERO
    inc     r12
    jmp     .cs_flags

.cs_width:
    xor     eax, eax
.csw_l:
    movzx   ecx, byte ptr [r12]
    sub     cl, '0'
    cmp     cl, 9
    ja      .csw_done
    imul    eax, eax, 10
    movzx   ecx, cl
    add     eax, ecx
    inc     r12
    jmp     .csw_l
.csw_done:
    cmp     eax, WIDTHMAX
    jbe     .csw_store
    mov     eax, WIDTHMAX
.csw_store:
    mov     [rbp + LOC_WIDTH], rax

.cs_prec:
    cmp     byte ptr [r12], '.'
    jne     .cs_conv
    inc     r12
    xor     eax, eax                        // precision defaults to 0 when '.' given
.csp_l:
    movzx   ecx, byte ptr [r12]
    sub     cl, '0'
    cmp     cl, 9
    ja      .csp_done
    imul    eax, eax, 10
    movzx   ecx, cl
    add     eax, ecx
    inc     r12
    jmp     .csp_l
.csp_done:
    cmp     eax, WIDTHMAX
    jbe     .csp_store
    mov     eax, WIDTHMAX
.csp_store:
    mov     [rbp + LOC_PREC], rax

.cs_conv:
    movzx   eax, byte ptr [r12]
    test    al, al
    jz      .bad_spec                       // '%' with no conversion char
    inc     r12
    cmp     al, 'd'
    je      .c_int_s
    cmp     al, 'i'
    je      .c_int_s
    cmp     al, 'u'
    je      .c_u
    cmp     al, 'o'
    je      .c_o
    cmp     al, 'x'
    je      .c_x
    cmp     al, 'X'
    je      .c_X
    cmp     al, 'c'
    je      .c_c
    cmp     al, 's'
    je      .c_s
    cmp     al, 'b'
    je      .c_b
    jmp     .bad_spec

.c_int_s:
    mov     byte ptr [rbp + LOC_BASE], 10
    call    next_arg
    mov     rdi, rax
    call    parse_num                       // rax = signed value
    test    rax, rax
    jns     .cis_pos
    mov     byte ptr [rbp + LOC_NEG], 1
    neg     rax
.cis_pos:
    mov     byte ptr [rbp + LOC_NONZERO], 0
    test    rax, rax
    jz      .cis_go
    mov     byte ptr [rbp + LOC_NONZERO], 1
.cis_go:
    call    conv_num
    jmp     .fmt_loop

.c_u:
    mov     byte ptr [rbp + LOC_BASE], 10
    mov     byte ptr [rbp + LOC_UNSIGNED], 1
    jmp     .num_unsigned
.c_o:
    mov     byte ptr [rbp + LOC_BASE], 8
    mov     byte ptr [rbp + LOC_UNSIGNED], 1
    jmp     .num_unsigned
.c_x:
    mov     byte ptr [rbp + LOC_BASE], 16
    mov     byte ptr [rbp + LOC_UNSIGNED], 1
    jmp     .num_unsigned
.c_X:
    mov     byte ptr [rbp + LOC_BASE], 16
    mov     byte ptr [rbp + LOC_UPPER], 1
    mov     byte ptr [rbp + LOC_UNSIGNED], 1
.num_unsigned:
    call    next_arg
    mov     rdi, rax
    call    parse_num                       // treat the bit pattern as unsigned
    mov     byte ptr [rbp + LOC_NONZERO], 0
    test    rax, rax
    jz      .nu_go
    mov     byte ptr [rbp + LOC_NONZERO], 1
.nu_go:
    call    conv_num
    jmp     .fmt_loop

.c_c:
    call    next_arg
    mov     rsi, rax
    cmp     byte ptr [rsi], 0
    jne     .cc_one
    xor     edx, edx                        // empty argument: width padding only
    jmp     .cc_emit
.cc_one:
    mov     rdx, 1
.cc_emit:
    call    emit_str
    jmp     .fmt_loop

.c_s:
    call    next_arg
    mov     rsi, rax
    mov     rdi, rax
    call    uolt_strlen                     // rax = length, rsi preserved
    mov     rdx, rax
    mov     rcx, [rbp + LOC_PREC]
    test    rcx, rcx
    js      .cs_emit                        // no precision
    cmp     rdx, rcx
    jbe     .cs_emit
    mov     rdx, rcx                        // truncate to precision
.cs_emit:
    call    emit_str
    jmp     .fmt_loop

// %b: copy the argument, translating backslash escapes, into BBUF (bounded),
// then emit it like %s. "\c" stops all further output immediately.
.c_b:
    call    next_arg
    mov     rsi, rax                        // src
    lea     rdi, [rbp + BBUFOFF]            // dst
    xor     r8, r8                          // produced length
.cb_l:
    cmp     r8, BSIZE
    jae     .cb_done                        // buffer full (documented cap)
    movzx   eax, byte ptr [rsi]
    test    al, al
    jz      .cb_done
    cmp     al, 0x5c                        // '\'
    jne     .cb_plain
    inc     rsi
    movzx   eax, byte ptr [rsi]
    test    al, al
    jz      .cb_lonebs                      // trailing backslash
    cmp     al, 'c'
    je      .cb_stop
    mov     cl, al                          // octal escape?
    sub     cl, '0'
    cmp     cl, 7
    jbe     .cb_oct
    call    named_esc                       // clc + translated al, or stc
    jc      .cb_unknown
    mov     [rdi], al
    inc     rdi
    inc     r8
    inc     rsi
    jmp     .cb_l
.cb_unknown:
    mov     byte ptr [rdi], 0x5c            // keep the backslash, then the byte
    inc     rdi
    inc     r8
    cmp     r8, BSIZE
    jae     .cb_done
    mov     [rdi], al
    inc     rdi
    inc     r8
    inc     rsi
    jmp     .cb_l
.cb_lonebs:
    mov     byte ptr [rdi], 0x5c
    inc     rdi
    inc     r8
    jmp     .cb_done
.cb_oct:
    xor     eax, eax                        // value
    xor     ecx, ecx                        // digit count
.cbo_l:
    movzx   edx, byte ptr [rsi]
    sub     dl, '0'
    cmp     dl, 7
    ja      .cbo_done
    shl     eax, 3
    movzx   edx, dl
    add     eax, edx
    inc     rsi
    inc     ecx
    cmp     ecx, 3
    jb      .cbo_l
.cbo_done:
    mov     [rdi], al
    inc     rdi
    inc     r8
    jmp     .cb_l
.cb_plain:
    mov     [rdi], al
    inc     rdi
    inc     r8
    inc     rsi
    jmp     .cb_l
.cb_done:
    lea     rsi, [rbp + BBUFOFF]
    mov     rdx, r8
    mov     rcx, [rbp + LOC_PREC]
    test    rcx, rcx
    js      .cb_emit
    cmp     rdx, rcx
    jbe     .cb_emit
    mov     rdx, rcx
.cb_emit:
    call    emit_str
    jmp     .fmt_loop
.cb_stop:
    lea     rsi, [rbp + BBUFOFF]
    mov     rdx, r8
    call    emit_str
    call    ob_flush
    xor     eax, eax
    jmp     .ret

// ---------------------------- helper routines --------------------------------

// next_arg() -> rax = pointer to the next ASCIZ argument, advancing the index.
// When the arguments are exhausted it returns the empty string and does NOT
// advance (so cycling terminates and defaults apply).
next_arg:
    mov     rax, [rbp + LOC_ARGI]
    cmp     rax, [rbp + LOC_ARGC]
    jae     .na_empty
    mov     rcx, [rbp + LOC_ARGP]
    mov     rax, [rcx + rax*8]
    inc     qword ptr [rbp + LOC_ARGI]
    ret
.na_empty:
    lea     rax, [rip + empty]
    ret

// do_escape(): translate a format-string escape whose char sits at [r12], emit
// it, and advance r12. An unrecognized escape prints the backslash literally and
// leaves the following byte for the normal path.
do_escape:
    movzx   eax, byte ptr [r12]
    mov     cl, al
    sub     cl, '0'
    cmp     cl, 7
    jbe     .de_oct
    call    named_esc
    jc      .de_unknown
    inc     r12
    jmp     ob_putc
.de_unknown:
    mov     al, 0x5c                        // leave [r12] to be printed next
    jmp     ob_putc
.de_oct:
    xor     eax, eax
    xor     ecx, ecx
.deo_l:
    movzx   edx, byte ptr [r12]
    sub     dl, '0'
    cmp     dl, 7
    ja      .deo_done
    shl     eax, 3
    movzx   edx, dl
    add     eax, edx
    inc     r12
    inc     ecx
    cmp     ecx, 3
    jb      .deo_l
.deo_done:
    jmp     ob_putc

// named_esc(al) -> al = translated byte with CF clear, or CF set (al unchanged)
// when the byte is not a single-letter escape. Touches only al and flags, so
// callers keep their pointers/counters.
named_esc:
    cmp     al, 0x5c                        // '\'
    je      .ne_bs
    cmp     al, 'a'
    je      .ne_a
    cmp     al, 'b'
    je      .ne_b
    cmp     al, 'f'
    je      .ne_f
    cmp     al, 'n'
    je      .ne_n
    cmp     al, 'r'
    je      .ne_r
    cmp     al, 't'
    je      .ne_t
    cmp     al, 'v'
    je      .ne_v
    cmp     al, '"'
    je      .ne_dq
    stc
    ret
.ne_bs:
    mov     al, 0x5c
    clc
    ret
.ne_a:
    mov     al, 7
    clc
    ret
.ne_b:
    mov     al, 8
    clc
    ret
.ne_f:
    mov     al, 12
    clc
    ret
.ne_n:
    mov     al, 10
    clc
    ret
.ne_r:
    mov     al, 13
    clc
    ret
.ne_t:
    mov     al, 9
    clc
    ret
.ne_v:
    mov     al, 11
    clc
    ret
.ne_dq:
    mov     al, '"'
    clc
    ret

// parse_num(rdi = ASCIZ) -> rax = value. Skips leading blanks; a leading ' or "
// yields the next byte's value; otherwise parses an optional sign then a C-style
// 0x hex / 0 octal / decimal constant. Trailing junk is ignored.
parse_num:
    xor     r8, r8                          // sign
    xor     rax, rax
.pn_skip:
    movzx   ecx, byte ptr [rdi]
    cmp     cl, ' '
    je      .pn_adv
    cmp     cl, 9
    jne     .pn_lead
.pn_adv:
    inc     rdi
    jmp     .pn_skip
.pn_lead:
    cmp     cl, 0x27                        // '
    je      .pn_char
    cmp     cl, 0x22                        // "
    je      .pn_char
    cmp     cl, '-'
    jne     .pn_plus
    mov     r8, 1
    inc     rdi
    jmp     .pn_radix
.pn_plus:
    cmp     cl, '+'
    jne     .pn_radix
    inc     rdi
.pn_radix:
    movzx   ecx, byte ptr [rdi]
    cmp     cl, '0'
    jne     .pn_dec
    movzx   edx, byte ptr [rdi + 1]
    or      dl, 0x20
    cmp     dl, 'x'
    je      .pn_hex
    jmp     .pn_oct
.pn_char:
    movzx   eax, byte ptr [rdi + 1]
    ret
.pn_dec:
    xor     rax, rax
.pnd_l:
    movzx   ecx, byte ptr [rdi]
    sub     cl, '0'
    cmp     cl, 9
    ja      .pn_fin
    imul    rax, rax, 10
    movzx   rcx, cl
    add     rax, rcx
    inc     rdi
    jmp     .pnd_l
.pn_oct:
    inc     rdi                             // skip the leading 0
    xor     rax, rax
.pno_l:
    movzx   ecx, byte ptr [rdi]
    sub     cl, '0'
    cmp     cl, 7
    ja      .pn_fin
    shl     rax, 3
    movzx   rcx, cl
    add     rax, rcx
    inc     rdi
    jmp     .pno_l
.pn_hex:
    add     rdi, 2                          // skip 0x
    xor     rax, rax
.pnh_l:
    movzx   ecx, byte ptr [rdi]
    cmp     cl, '0'
    jb      .pn_fin
    cmp     cl, '9'
    jbe     .pnh_dig
    or      cl, 0x20
    cmp     cl, 'a'
    jb      .pn_fin
    cmp     cl, 'f'
    ja      .pn_fin
    sub     cl, 'a' - 10
    jmp     .pnh_add
.pnh_dig:
    sub     cl, '0'
.pnh_add:
    shl     rax, 4
    movzx   rcx, cl
    add     rax, rcx
    inc     rdi
    jmp     .pnh_l
.pn_fin:
    test    r8, r8
    jz      .pn_ret
    neg     rax
.pn_ret:
    ret

// conv_num(rax = magnitude, unsigned): format the number per LOC_BASE / LOC_*
// (sign, precision, '#' prefix, zero/space width padding) and emit it. Keeps
// dptr=r8, plen=r9, dlen=r10 live across the emit helpers (which use only stack
// locals + caller-saved scratch, so those registers survive).
conv_num:
    lea     r8, [rbp + NUMEND]              // build digits downward from here
    movzx   r10, byte ptr [rbp + LOC_BASE]
    test    rax, rax
    jnz     .cn_digits
    cmp     qword ptr [rbp + LOC_PREC], 0
    je      .cn_precdone                    // value 0, precision 0 -> no digits
    dec     r8
    mov     byte ptr [r8], '0'
    jmp     .cn_precdone
.cn_digits:
    xor     rdx, rdx
    mov     rcx, r10
    div     rcx                             // rax /= base, rdx = digit
    mov     cl, dl
    cmp     cl, 9
    jbe     .cn_dig09
    sub     cl, 10
    add     cl, 'a'
    cmp     byte ptr [rbp + LOC_UPPER], 0
    je      .cn_digput
    and     cl, 0xDF                        // 'a'..'f' -> 'A'..'F'
    jmp     .cn_digput
.cn_dig09:
    add     cl, '0'
.cn_digput:
    dec     r8
    mov     [r8], cl
    test    rax, rax
    jnz     .cn_digits
.cn_precdone:
    // precision: pad the digit field with leading zeros to LOC_PREC.
    mov     rax, [rbp + LOC_PREC]
    test    rax, rax
    js      .cn_octhash
    lea     rcx, [rbp + NUMEND]
    sub     rcx, r8                         // current digit count
.cn_pz:
    cmp     rcx, rax
    jae     .cn_octhash
    dec     r8
    mov     byte ptr [r8], '0'
    inc     rcx
    jmp     .cn_pz
.cn_octhash:
    // '#': octal gets a guaranteed leading 0 (folded into the digit field).
    test    byte ptr [rbp + LOC_FLAGS], FLAG_HASH
    jz      .cn_prefix
    cmp     byte ptr [rbp + LOC_BASE], 8
    jne     .cn_prefix
    cmp     byte ptr [r8], '0'
    je      .cn_prefix
    dec     r8
    mov     byte ptr [r8], '0'
.cn_prefix:
    // Build the sign / hex '#' prefix into PFX (length -> r9).
    lea     r11, [rbp + PFXOFF]
    xor     r9, r9
    cmp     byte ptr [rbp + LOC_UNSIGNED], 0
    jne     .cn_hexhash
    cmp     byte ptr [rbp + LOC_NEG], 0
    je      .cn_possign
    mov     byte ptr [r11 + r9], '-'
    inc     r9
    jmp     .cn_hexhash
.cn_possign:
    test    byte ptr [rbp + LOC_FLAGS], FLAG_PLUS
    jz      .cn_spaceflag
    mov     byte ptr [r11 + r9], '+'
    inc     r9
    jmp     .cn_hexhash
.cn_spaceflag:
    test    byte ptr [rbp + LOC_FLAGS], FLAG_SPACE
    jz      .cn_hexhash
    mov     byte ptr [r11 + r9], ' '
    inc     r9
.cn_hexhash:
    test    byte ptr [rbp + LOC_FLAGS], FLAG_HASH
    jz      .cn_measure
    cmp     byte ptr [rbp + LOC_BASE], 16
    jne     .cn_measure
    cmp     byte ptr [rbp + LOC_NONZERO], 0
    je      .cn_measure
    mov     byte ptr [r11 + r9], '0'
    inc     r9
    mov     cl, 'x'
    cmp     byte ptr [rbp + LOC_UPPER], 0
    je      .cn_hh_put
    mov     cl, 'X'
.cn_hh_put:
    mov     [r11 + r9], cl
    inc     r9
.cn_measure:
    lea     rax, [rbp + NUMEND]
    sub     rax, r8                         // digit-field length
    mov     r10, rax                        // r10 = dlen
    lea     rax, [r9 + r10]                 // core length = plen + dlen
    mov     rcx, [rbp + LOC_WIDTH]
    sub     rcx, rax                        // pad = width - core
    jle     .cn_plain
    mov     [rbp + LOC_CNPAD], rcx
    test    byte ptr [rbp + LOC_FLAGS], FLAG_MINUS
    jnz     .cn_left
    test    byte ptr [rbp + LOC_FLAGS], FLAG_ZERO
    jz      .cn_spaceright
    cmp     qword ptr [rbp + LOC_PREC], 0
    jns     .cn_spaceright                  // precision disables 0-pad for integers
    // zero pad: prefix, then zeros, then digits.
    mov     rsi, r11
    mov     rdx, r9
    call    ob_put
    mov     rdi, [rbp + LOC_CNPAD]
    mov     esi, '0'
    call    emit_pad
    mov     rsi, r8
    mov     rdx, r10
    jmp     ob_put
.cn_spaceright:
    mov     rdi, [rbp + LOC_CNPAD]
    mov     esi, ' '
    call    emit_pad
    mov     rsi, r11
    mov     rdx, r9
    call    ob_put
    mov     rsi, r8
    mov     rdx, r10
    jmp     ob_put
.cn_left:
    mov     rsi, r11
    mov     rdx, r9
    call    ob_put
    mov     rsi, r8
    mov     rdx, r10
    call    ob_put
    mov     rdi, [rbp + LOC_CNPAD]
    mov     esi, ' '
    jmp     emit_pad
.cn_plain:
    mov     rsi, r11
    mov     rdx, r9
    call    ob_put
    mov     rsi, r8
    mov     rdx, r10
    jmp     ob_put

// emit_str(rsi = ptr, rdx = len): write the string padded to LOC_WIDTH with
// spaces, honoring FLAG_MINUS (left justify). Precision is applied by the caller.
emit_str:
    mov     [rbp + LOC_SPTR], rsi
    mov     [rbp + LOC_SLEN], rdx
    mov     rax, [rbp + LOC_WIDTH]
    sub     rax, rdx
    jle     .es_plain
    mov     [rbp + LOC_ESPAD], rax
    test    byte ptr [rbp + LOC_FLAGS], FLAG_MINUS
    jnz     .es_left
    mov     rdi, [rbp + LOC_ESPAD]
    mov     esi, ' '
    call    emit_pad
    mov     rsi, [rbp + LOC_SPTR]
    mov     rdx, [rbp + LOC_SLEN]
    jmp     ob_put
.es_left:
    mov     rsi, [rbp + LOC_SPTR]
    mov     rdx, [rbp + LOC_SLEN]
    call    ob_put
    mov     rdi, [rbp + LOC_ESPAD]
    mov     esi, ' '
    jmp     emit_pad
.es_plain:
    mov     rsi, [rbp + LOC_SPTR]
    mov     rdx, [rbp + LOC_SLEN]
    jmp     ob_put

// emit_pad(rdi = count, sil = fill byte): emit the fill byte count times.
emit_pad:
    mov     [rbp + LOC_PADN2], rdi
    mov     [rbp + LOC_PADCH], sil
.ep_l:
    cmp     qword ptr [rbp + LOC_PADN2], 0
    jle     .ep_ret
    mov     al, [rbp + LOC_PADCH]
    call    ob_putc
    dec     qword ptr [rbp + LOC_PADN2]
    jmp     .ep_l
.ep_ret:
    ret

// -------------------- buffered output (OBUF) ---------------------------------

// ob_putc(al): append one byte to OBUF, flushing first if it is full.
ob_putc:
    mov     rcx, [rbp + OBLEN]
    cmp     rcx, OBSIZE
    jb      .opc_store
    call    ob_flush
    xor     rcx, rcx
.opc_store:
    lea     rdx, [rbp + OBOFF]
    mov     [rdx + rcx], al
    inc     rcx
    mov     [rbp + OBLEN], rcx
    ret

// ob_put(rsi = ptr, rdx = len): append len bytes, byte at a time (OBUF batches
// the actual syscalls). Uses only stack locals + scratch so callers' r8..r15 and
// rbx survive.
ob_put:
    mov     [rbp + LOC_PPTR], rsi
    mov     [rbp + LOC_PLEN], rdx
.obp_l:
    cmp     qword ptr [rbp + LOC_PLEN], 0
    jle     .obp_ret
    mov     rcx, [rbp + LOC_PPTR]
    mov     al, [rcx]
    call    ob_putc
    inc     qword ptr [rbp + LOC_PPTR]
    dec     qword ptr [rbp + LOC_PLEN]
    jmp     .obp_l
.obp_ret:
    ret

// ob_flush(): write OBUF to stdout and reset it.
ob_flush:
    mov     rdx, [rbp + OBLEN]
    test    rdx, rdx
    jz      .obf_ret
    lea     rsi, [rbp + OBOFF]
    mov     rdi, STDOUT
    call    uolt_write
    mov     qword ptr [rbp + OBLEN], 0
.obf_ret:
    ret

// err_puts(rdi = ASCIZ): write a diagnostic to stderr.
err_puts:
    mov     r10, rdi
    call    uolt_strlen
    mov     rdx, rax
    mov     rsi, r10
    mov     rdi, STDERR
    jmp     uolt_write

empty:      .asciz ""
err_usage:  .asciz "uolt-printf: usage: printf format [argument...]\n"
err_spec:   .asciz "uolt-printf: invalid conversion specification\n"
