#!/bin/sh
# Differential test: uolt-yes matches the reference `yes` on a large sample.
# Only the no-operand and single-operand cases are compared: multi-operand yes
# diverges (GNU joins all operands, BSD uses only the first), so that case is
# left to the unit/posix tests.
set -u
BIN=${UOLT_YES:-${BUILD:-./build}/uolt-yes}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
REF=/usr/bin/yes; [ -x /bin/yes ] && REF=/bin/yes
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

# No operands.
"$BIN" | head -2000 >"$tmp/u"
"$REF" | head -2000 >"$tmp/r"
cmp -s "$tmp/u" "$tmp/r" || { echo "FAIL diff: default output differs"; fail=1; }

# Single operand (BSD and GNU agree here).
"$BIN" moo | head -2000 >"$tmp/u"
"$REF" moo | head -2000 >"$tmp/r"
cmp -s "$tmp/u" "$tmp/r" || { echo "FAIL diff: single-operand output differs"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS differential/yes (ref: $REF)"
exit "$fail"
