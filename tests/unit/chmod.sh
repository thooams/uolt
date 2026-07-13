#!/bin/sh
# Unit test for uolt-chmod: set octal permission bits on files, reject symbolic
# modes (v1), and handle the error / operand cases.
set -u
BIN=${UOLT_CHMOD:-${BUILD:-./build}/uolt-chmod}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0
cd "$tmp" || exit 1

perm() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }

touch f g

"$BIN" 755 f; { [ $? -eq 0 ] && [ "$(perm f)" = "755" ]; } || { echo "FAIL unit: 755 [$(perm f)]"; fail=1; }
"$BIN" 0600 f; { [ $? -eq 0 ] && [ "$(perm f)" = "600" ]; } || { echo "FAIL unit: 0600 [$(perm f)]"; fail=1; }
"$BIN" 644 f g; { [ "$(perm f)" = "644" ] && [ "$(perm g)" = "644" ]; } || { echo "FAIL unit: multi"; fail=1; }
"$BIN" 640 f; [ "$(perm f)" = "640" ] || { echo "FAIL unit: 640 [$(perm f)]"; fail=1; }

# Symbolic mode is rejected (unsupported in v1).
"$BIN" u+x f 2>/dev/null; [ $? -ne 0 ] || { echo "FAIL unit: symbolic accepted"; fail=1; }

# Missing file, and operand-count errors.
"$BIN" 755 nope 2>/dev/null; [ $? -ne 0 ] || { echo "FAIL unit: missing file exit 0"; fail=1; }
"$BIN" 755 2>/dev/null;      [ $? -ne 0 ] || { echo "FAIL unit: no file exit 0"; fail=1; }
"$BIN" >/dev/null 2>&1;      [ $? -ne 0 ] || { echo "FAIL unit: no operand exit 0"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS unit/chmod"
exit "$fail"
