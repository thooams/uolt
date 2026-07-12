#!/bin/sh
# Unit test for uolt-pwd: prints the physical cwd + newline, exits 0.
#
# The comparison runs inside a fresh mktemp directory (a canonical path) rather
# than the current directory: on a case-insensitive macOS filesystem the shell's
# cwd string may differ in case from the true on-disk name, which uolt-pwd
# reports faithfully. A canonical temp dir avoids that ambiguity.
set -u
BIN=${UOLT_PWD:-${BUILD:-./build}/uolt-pwd}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
REF=/bin/pwd; [ -x /usr/bin/pwd ] && REF=/usr/bin/pwd
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

out=$(cd "$tmp" && "$BIN"); rc=$?
[ "$rc" -eq 0 ]        || { echo "FAIL unit: exit $rc"; fail=1; }
case "$out" in
    /*) ;;
    *) echo "FAIL unit: not absolute [$out]"; fail=1;;
esac

# Trailing newline present.
(cd "$tmp" && "$BIN") >"$tmp/o"
last=$(tail -c1 "$tmp/o" | od -An -tu1 | tr -d ' ')
[ "$last" = "10" ] || { echo "FAIL unit: no trailing newline"; fail=1; }

# Matches the reference pwd -P from the same canonical directory.
want=$(cd "$tmp" && "$REF" -P)
[ "$out" = "$want" ] || { echo "FAIL unit: [$out] != [$want]"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS unit/pwd"
exit "$fail"
