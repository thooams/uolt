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

# Symbolic modes.
chmod 644 f; "$BIN" u+x f;   [ "$(perm f)" = "744" ] || { echo "FAIL unit: u+x [$(perm f)]"; fail=1; }
chmod 644 f; "$BIN" go-r f;  [ "$(perm f)" = "600" ] || { echo "FAIL unit: go-r [$(perm f)]"; fail=1; }
chmod 644 f; "$BIN" a=r f;   [ "$(perm f)" = "444" ] || { echo "FAIL unit: a=r [$(perm f)]"; fail=1; }
chmod 644 f; "$BIN" u+x,g+w f; [ "$(perm f)" = "764" ] || { echo "FAIL unit: multi [$(perm f)]"; fail=1; }
mkdir dd; chmod 644 dd; "$BIN" a+X dd; [ "$(perm dd)" = "755" ] || { echo "FAIL unit: a+X dir [$(perm dd)]"; fail=1; }

# Missing file, and operand-count errors.
"$BIN" 755 nope 2>/dev/null; [ $? -ne 0 ] || { echo "FAIL unit: missing file exit 0"; fail=1; }
"$BIN" 755 2>/dev/null;      [ $? -ne 0 ] || { echo "FAIL unit: no file exit 0"; fail=1; }
"$BIN" >/dev/null 2>&1;      [ $? -ne 0 ] || { echo "FAIL unit: no operand exit 0"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS unit/chmod"
exit "$fail"
