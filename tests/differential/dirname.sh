#!/bin/sh
# Differential test: uolt-dirname matches the reference `dirname` on stdout and
# exit code across a range of path shapes (the POSIX single-operand form, where
# GNU and BSD agree).
set -u
BIN=${UOLT_DIRNAME:-${BUILD:-./build}/uolt-dirname}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
REF=/usr/bin/dirname; [ -x /bin/dirname ] && REF=/bin/dirname
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
compare a/b
compare a/b/
compare a
compare /a
compare a/
compare a//b
compare a//b//c
compare /a/b/c/
compare dir/file.txt
compare "with space/file name.log"

[ "$fail" -eq 0 ] && echo "PASS differential/dirname (ref: $REF)"
exit "$fail"
