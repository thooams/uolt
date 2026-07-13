#!/bin/sh
# Differential test: uolt-basename matches the reference `basename` on stdout
# and exit code across a range of path shapes (the POSIX one/two-operand form,
# where GNU and BSD agree).
set -u
BIN=${UOLT_BASENAME:-${BUILD:-./build}/uolt-basename}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
REF=/usr/bin/basename; [ -x /bin/basename ] && REF=/bin/basename
fail=0

compare() {
    u=$("$BIN" "$@" 2>/dev/null); urc=$?
    s=$("$REF" "$@" 2>/dev/null); src=$?
    [ "$urc" -eq "$src" ] || { echo "FAIL diff [$*]: exit $urc vs ref $src"; fail=1; }
    [ "$u" = "$s" ]       || { echo "FAIL diff [$*]: [$u] != [$s]"; fail=1; }
}

compare /usr/lib
compare /usr/lib/
compare /usr/
compare usr
compare /
compare //
compare ///
compare .
compare ..
compare a.txt .txt
compare a.txt .x
compare .txt .txt
compare /foo/bar.c .c
compare a//b//
compare /a/b/c.tar.gz .gz
compare name.ext .ext
compare name.ext .other
compare /path/to/dir/
compare "with space/file name.log" .log

[ "$fail" -eq 0 ] && echo "PASS differential/basename (ref: $REF)"
exit "$fail"
